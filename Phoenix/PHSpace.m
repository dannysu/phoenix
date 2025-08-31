/*
 * Phoenix is released under the MIT License. Refer to https://github.com/kasper/phoenix/blob/master/LICENSE.md
 */

@import Cocoa;

#import "PHSpace.h"
#import "NSArray+PHExtension.h"
#import "NSProcessInfo+PHExtension.h"
#import "NSScreen+PHExtension.h"
#import "PHWindow.h"

/* XXX: Undocumented private typedefs for CGSSpace */

typedef NSUInteger CGSConnectionID;
typedef NSUInteger CGSSpaceID;
typedef NSUInteger CGSWorkspaceID;

typedef enum {
    kCGSSpaceIncludesCurrent = 1 << 0,
    kCGSSpaceIncludesOthers = 1 << 1,
    kCGSSpaceIncludesUser = 1 << 2,
    kCGSAllSpacesMask = kCGSSpaceIncludesCurrent | kCGSSpaceIncludesOthers | kCGSSpaceIncludesUser
} CGSSpaceMask;

typedef enum { kCGSSpaceUser, kCGSSpaceFullScreen = 4 } CGSSpaceType;

@interface PHSpace ()

@property CGSSpaceID identifier;

@end

@implementation PHSpace

static NSString *const CGSScreenIDKey = @"Display Identifier";
static NSString *const CGSSpaceIDKey = @"ManagedSpaceID";
static NSString *const CGSSpacesKey = @"Spaces";

// XXX: Undocumented private API to get the CGSConnectionID for the default connection for this process
CGSConnectionID CGSMainConnectionID(void);

// XXX: Undocumented private API to get the CGSSpaceID for the active space
CGSSpaceID CGSGetActiveSpace(CGSConnectionID connection);

// XXX: Undocumented private API to get the CGSSpaceID for the current space for a given screen (UUID)
CGSSpaceID CGSManagedDisplayGetCurrentSpace(CGSConnectionID connection, CFStringRef screenId);

// XXX: Undocumented private API to get the CGSSpaceIDs for all spaces in order
CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection);

// XXX: Undocumented private API to get the CGSSpaceIDs for the given windows (CGWindowIDs)
CFArrayRef CGSCopySpacesForWindows(CGSConnectionID connection, CGSSpaceMask mask, CFArrayRef windowIds);

// XXX: Undocumented private API to get the CGSSpaceType for a given space
CGSSpaceType CGSSpaceGetType(CGSConnectionID connection, CGSSpaceID space);

// XXX: Undocumented private API to add the given windows (CGWindowIDs) to the given spaces (CGSSpaceIDs)
void CGSAddWindowsToSpaces(CGSConnectionID connection, CFArrayRef windowIds, CFArrayRef spaceIds);

// XXX: Undocumented private API to remove the given windows (CGWindowIDs) from the given spaces (CGSSpaceIDs)
void CGSRemoveWindowsFromSpaces(CGSConnectionID connection, CFArrayRef windowIds, CFArrayRef spaceIds);

// XXX: Undocumented private API to move the given windows (CGWindowIDs) to the given space,
// only works prior to macOS 14.5
void CGSMoveWindowsToManagedSpace(CGSConnectionID connection, CFArrayRef windowIds, CGSSpaceID spaceId);

#pragma mark - Initialising

- (instancetype)initWithIdentifier:(NSUInteger)identifier {
    if (self = [super init]) {
        self.identifier = identifier;
    }

    return self;
}

#pragma mark - Spaces

+ (instancetype)active {
    return [(PHSpace *)[self alloc] initWithIdentifier:CGSGetActiveSpace(CGSMainConnectionID())];
}

+ (NSArray<PHSpace *> *)all {
    NSMutableArray *spaces = [NSMutableArray array];
    NSArray *displaySpacesInfo = CFBridgingRelease(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()));

    for (NSDictionary<NSString *, id> *spacesInfo in displaySpacesInfo) {
        NSArray<NSNumber *> *identifiers = [spacesInfo[CGSSpacesKey] valueForKey:CGSSpaceIDKey];

        for (NSNumber *identifier in identifiers) {
            [spaces addObject:[(PHSpace *)[self alloc] initWithIdentifier:identifier.unsignedLongValue]];
        }
    }

    return spaces;
}

+ (instancetype)currentSpaceForScreen:(NSScreen *)screen {
    NSUInteger identifier =
        CGSManagedDisplayGetCurrentSpace(CGSMainConnectionID(), (__bridge CFStringRef)[screen identifier]);

    return [(PHSpace *)[self alloc] initWithIdentifier:identifier];
}

+ (NSArray<PHSpace *> *)spacesForWindow:(PHWindow *)window {
    NSMutableArray *spaces = [NSMutableArray array];
    NSArray<NSNumber *> *identifiers = CFBridgingRelease(CGSCopySpacesForWindows(
        CGSMainConnectionID(), kCGSAllSpacesMask, (__bridge CFArrayRef) @[@([window identifier])]));
    for (PHSpace *space in [self all]) {
        NSNumber *identifier = @([space hash]);

        if ([identifiers containsObject:identifier]) {
            [spaces addObject:[(PHSpace *)[self alloc] initWithIdentifier:identifier.unsignedLongValue]];
        }
    }

    return spaces;
}

#pragma mark - Identifying

- (NSUInteger)hash {
    return self.identifier;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[PHSpace class]] && [self hash] == [object hash];
}

#pragma mark - PHIterableJSExport

- (instancetype)next {
    return [[PHSpace all] nextFrom:self];
}

- (instancetype)previous {
    return [[PHSpace all] previousFrom:self];
}

#pragma mark - Properties

- (BOOL)isNormal {
    return CGSSpaceGetType(CGSMainConnectionID(), self.identifier) == kCGSSpaceUser;
}

- (BOOL)isFullScreen {
    return CGSSpaceGetType(CGSMainConnectionID(), self.identifier) == kCGSSpaceFullScreen;
}

- (NSArray<NSScreen *> *)screens {
    if (![NSScreen screensHaveSeparateSpaces]) {
        return [NSScreen screens];
    }

    NSArray *displaySpacesInfo = CFBridgingRelease(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()));

    for (NSDictionary<NSString *, id> *spacesInfo in displaySpacesInfo) {
        NSString *screenIdentifier = spacesInfo[CGSScreenIDKey];
        NSArray<NSNumber *> *identifiers = [spacesInfo[CGSSpacesKey] valueForKey:CGSSpaceIDKey];

        if ([identifiers containsObject:@(self.identifier)]) {
            NSScreen *screen = [NSScreen screenForIdentifier:screenIdentifier];
            return screen ? @[screen] : @[];
        }
    }

    return @[];
}

#pragma mark - Windows

- (NSArray<PHWindow *> *)windows {
    return [PHWindow
        filteredWindowsUsingPredicateBlock:^BOOL(PHWindow *window, __unused NSDictionary<NSString *, id> *bindings) {
            return [[window spaces] containsObject:self];
        }];
}

- (NSArray<PHWindow *> *)windows:(NSDictionary<NSString *, id> *)optionals {
    NSNumber *visibilityOption = optionals[PHWindowVisibilityOptionKey];

    // Filter based on visibility
    if (visibilityOption) {
        return [[self windows] filteredArrayUsingPredicate:[PHWindow isVisible:visibilityOption.boolValue]];
    }

    return [self windows];
}

- (NSArray<NSNumber *> *)identifiersForWindows:(NSArray<PHWindow *> *)windows {
    NSMutableArray<NSNumber *> *identifiers = [NSMutableArray array];

    for (PHWindow *window in windows) {
        if ([window respondsToSelector:@selector(identifier)]) {
            [identifiers addObject:@([window identifier])];
        }
    }

    return identifiers;
}

- (void)addWindows:(NSArray<PHWindow *> *)windows {
    if ([NSProcessInfo isOperatingSystemAtLeastMonterey]) {
        NSLog(@"Deprecated: Function Space#addWindows(...) is deprecated and will be removed in later versions, use "
              @"Space#moveWindows(...) instead.");
        return;
    }

    CGSAddWindowsToSpaces(CGSMainConnectionID(),
                          (__bridge CFArrayRef)[self identifiersForWindows:windows],
                          (__bridge CFArrayRef) @[@(self.identifier)]);
}

- (void)removeWindows:(NSArray<PHWindow *> *)windows {
    if ([NSProcessInfo isOperatingSystemAtLeastMonterey]) {
        NSLog(@"Deprecated: Function Space#removeWindows(...) is deprecated and will be removed in later versions, use "
              @"Space#moveWindows(...) instead.");
        return;
    }

    CGSRemoveWindowsFromSpaces(CGSMainConnectionID(),
                               (__bridge CFArrayRef)[self identifiersForWindows:windows],
                               (__bridge CFArrayRef) @[@(self.identifier)]);
}

- (void)moveWindows:(NSArray<PHWindow *> *)windows {
    // Moving windows is not anymore supported in macOS 13.6+, 14.5+ and 15.0+
    if ([NSProcessInfo isOperatingSystemAtLeastVentura136] || [NSProcessInfo isOperatingSystemAtLeastSonoma145] ||
        [NSProcessInfo isOperatingSystemAtLeastSequoia]) {
        NSLog(@"Deprecated: Function Space#moveWindows(...) is deprecated and will be removed in later versions.");
        return;
    }

    CGSMoveWindowsToManagedSpace(
        CGSMainConnectionID(), (__bridge CFArrayRef)[self identifiersForWindows:windows], self.identifier);
}

@end
