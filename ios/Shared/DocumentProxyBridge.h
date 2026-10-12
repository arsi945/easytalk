#import <UIKit/UIKit.h>

// UIKit can return nil before the extension is attached to a document, despite
// declaring this property nonnull. Keep the Objective-C result nullable so Swift
// does not force-bridge nil to UUID during keyboard startup or detachment.
FOUNDATION_EXPORT NSUUID * _Nullable EasyTalkDocumentIdentifier(id<UITextDocumentProxy> _Nonnull proxy);
