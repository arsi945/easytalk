#import "DocumentProxyBridge.h"

NSUUID * _Nullable EasyTalkDocumentIdentifier(id<UITextDocumentProxy> proxy) {
    return proxy.documentIdentifier;
}
