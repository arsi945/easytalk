#!/usr/bin/env python3
"""Create one "Apple Development" certificate through the App Store Connect API and save it with its
private key as a PKCS#12 file, so CI keeps reusing it instead of letting Xcode create a new
certificate on every fresh runner (the account allows only a few).

Usage: create_signing_identity.py OUT.p12   (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, IDENTITY_PASS)
Needs: pyjwt, cryptography. Prints no secrets.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID


def api_token() -> str:
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as handle:
        key = handle.read()
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def main(out_path: str) -> None:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "easytalk CI")])
    csr = x509.CertificateSigningRequestBuilder().subject_name(subject).sign(private_key, hashes.SHA256())
    body = {"data": {"type": "certificates", "attributes": {
        "certificateType": "DEVELOPMENT",
        "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode(),
    }}}
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/certificates",
        data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + api_token(), "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            answer = json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        print(f"::error::App Store Connect refused to create a certificate (HTTP {error.code}): {details}")
        if "maximum" in details.lower():
            print("::error::Revoke old 'Apple Development' certificates at developer.apple.com, then run again.")
        sys.exit(1)

    certificate = x509.load_der_x509_certificate(base64.b64decode(answer["data"]["attributes"]["certificateContent"]))
    # macOS `security import` reads the legacy PKCS#12 encryption, not AES.
    encryption = (serialization.PrivateFormat.PKCS12.encryption_builder()
                  .kdf_rounds(50000)
                  .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
                  .hmac_hash(hashes.SHA1())
                  .build(os.environ["IDENTITY_PASS"].encode()))
    data = pkcs12.serialize_key_and_certificates(b"easytalk CI", private_key, certificate, None, encryption)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as handle:
        handle.write(data)
    print(f"Created Apple Development certificate {answer['data']['id']}, valid until {certificate.not_valid_after_utc:%Y-%m-%d}")


if __name__ == "__main__":
    main(sys.argv[1])
