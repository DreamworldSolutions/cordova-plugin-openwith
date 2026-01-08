//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import "ShareViewController.h"

@interface ShareViewController () {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
    NSLog(@"ShareViewController - setup: Group identifier = %@", SHAREEXT_GROUP_IDENTIFIER);
    NSLog(@"ShareViewController - setup: URL scheme = %@", SHAREEXT_URL_SCHEME);
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    if (!self.userDefaults) {
        NSLog(@"ShareViewController - ERROR: Failed to initialize userDefaults with suite name");
    } else {
        NSLog(@"ShareViewController - userDefaults initialized successfully");
    }
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    NSLog(@"ShareViewController - Verbosity level: %d", self.verbosityLevel);
    [self debug:@"[setup]"];
}

- (void) viewDidLoad {
    [super viewDidLoad];
    NSLog(@"ShareViewController - viewDidLoad started");
    [self setup];
    [self debug:@"[viewDidLoad]"];

    // Immediately process the shared content
    [self handleSharedContent];
    NSLog(@"ShareViewController - viewDidLoad completed");
}

- (void) openURL:(nonnull NSURL *)url {
    NSLog(@"ShareViewController - openURL called with: %@", url);
    [self debug:[NSString stringWithFormat:@"[openURL] %@", url]];

    // App Extensions cannot directly open URLs using UIApplication
    // Instead, use the extension context's openURL method (iOS 10+)
    if (@available(iOS 10.0, *)) {
        NSLog(@"ShareViewController - Attempting to open URL via extensionContext");
        [self.extensionContext openURL:url completionHandler:^(BOOL success) {
            NSLog(@"ShareViewController - openURL completion: success=%d", success);
            if (success) {
                [self debug:@"[openURL] Successfully opened URL"];
            } else {
                [self error:@"[openURL] Failed to open URL - the URL may not be registered or the app may not be installed"];
            }
        }];
    } else {
        NSLog(@"ShareViewController - ERROR: iOS 10+ required");
        [self error:@"[openURL] openURL requires iOS 10 or later"];
    }
}

- (void) handleSharedContent {
    NSLog(@"ShareViewController - handleSharedContent started");
    [self debug:@"[handleSharedContent]"];

    if (!self.extensionContext) {
        NSLog(@"ShareViewController - ERROR: No extension context");
        [self error:@"[handleSharedContent] No extension context"];
        return;
    }

    NSExtensionItem *inputItem = self.extensionContext.inputItems.firstObject;
    if (!inputItem) {
        NSLog(@"ShareViewController - ERROR: No input items");
        [self error:@"[handleSharedContent] No input items"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    NSLog(@"ShareViewController - Found input item with %lu attachments", (unsigned long)inputItem.attachments.count);

    // Get content text if available
    NSString *contentText = inputItem.attributedContentText.string ?: @"";
    NSLog(@"ShareViewController - Content text: %@", contentText);
    NSLog(@"ShareViewController - Looking for type identifier: %@", SHAREEXT_UNIFORM_TYPE_IDENTIFIER);

    // Process attachments
    for (NSItemProvider* itemProvider in inputItem.attachments) {
        NSLog(@"ShareViewController - Processing attachment: %@", itemProvider.registeredTypeIdentifiers);

        if ([itemProvider hasItemConformingToTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER]) {
            NSLog(@"ShareViewController - Found matching type identifier");
            [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

            [itemProvider loadItemForTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER options:nil completionHandler: ^(id<NSSecureCoding> item, NSError *error) {
                NSLog(@"ShareViewController - loadItemForTypeIdentifier completed");

                if (error) {
                    NSLog(@"ShareViewController - ERROR loading item: %@", error.localizedDescription);
                    [self error:[NSString stringWithFormat:@"[handleSharedContent] Error loading item: %@", error.localizedDescription]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                    });
                    return;
                }

                NSLog(@"ShareViewController - Item loaded successfully, type: %@", NSStringFromClass([item class]));

                NSData *data = [[NSData alloc] init];
                if([(NSObject*)item isKindOfClass:[NSURL class]]) {
                    data = [NSData dataWithContentsOfURL:(NSURL*)item];
                }
                if([(NSObject*)item isKindOfClass:[UIImage class]]) {
                    data = UIImagePNGRepresentation((UIImage*)item);
                }

                NSString *suggestedName = @"";
                if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")]) {
                    suggestedName = [itemProvider valueForKey:@"suggestedName"];
                }

                NSString *uti = @"";
                NSArray<NSString *> *utis = [NSArray new];
                if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                    uti = itemProvider.registeredTypeIdentifiers[0];
                    utis = itemProvider.registeredTypeIdentifiers;
                }
                else {
                    uti = SHAREEXT_UNIFORM_TYPE_IDENTIFIER;
                }
                NSDictionary *dict = @{
                    @"text": contentText,
                    @"backURL": self.backURL ?: @"",
                    @"data" : data,
                    @"uti": uti,
                    @"utis": utis,
                    @"name": suggestedName
                };
                NSLog(@"ShareViewController - Saving data to userDefaults with key 'image'");
                NSLog(@"ShareViewController - Data size: %lu bytes, text: %@", (unsigned long)data.length, contentText);
                [self.userDefaults setObject:dict forKey:@"image"];
                // Note: synchronize is deprecated but happens automatically

                // Emit a URL that opens the cordova app
                NSString *urlString = [NSString stringWithFormat:@"%@://image", SHAREEXT_URL_SCHEME];
                NSLog(@"ShareViewController - Constructed URL: %@", urlString);
                [self debug:[NSString stringWithFormat:@"[handleSharedContent] Opening URL: %@", urlString]];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self openURL:[NSURL URLWithString:urlString]];

                    // Inform the host that we're done, so it un-blocks its UI.
                    // Delay slightly to ensure the URL is opened first
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        NSLog(@"ShareViewController - Completing extension request");
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:^(BOOL expired) {
                            NSLog(@"ShareViewController - Extension request completed, expired=%d", expired);
                        }];
                    });
                });
            }];

            return;
        }
    }

    // No matching items found
    NSLog(@"ShareViewController - ERROR: No matching items found for type identifier: %@", SHAREEXT_UNIFORM_TYPE_IDENTIFIER);
    [self error:@"[handleSharedContent] No matching items found"];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    self.backURL = [self backURLFromBundleID:hostBundleID];
}

@end
