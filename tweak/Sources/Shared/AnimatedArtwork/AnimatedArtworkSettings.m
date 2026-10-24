// The lock screen's ordered artwork views and whether moving-artwork downloads run in Low Data Mode.
// iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGSourcesPage.h"
#import "AnimatedArtwork.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"

static NSString *const kStarCanvas = @"canvas";
static NSString *const kStarCanvasLyrics = @"canvasLyrics";
static NSString *const kStarFill = @"fill";
static NSString *const kStarDefault = @"default";
static NSString *const kStarColorful = @"colorful";
static NSString *const kArtistLyricsWasEnabled = @"spotifyglass.lockscreen.artistLyricsWasEnabled";
static NSString *const kStarViewsMigrated = @"spotifyglass.lockscreen.starViews.migrated";
static NSArray<NSString *> *defaultStarViewOrder(void) {
    return @[kStarCanvas, kStarCanvasLyrics, kStarFill, kStarColorful, kStarDefault];
}

static BOOL starViewOrderContains(NSString *key) {
    return [SGLockScreenStarViewOrder() containsObject:key];
}

static NSString *starViewName(NSString *key) {
    if ([key isEqualToString:kStarCanvas]) return @"Canvas";
    if ([key isEqualToString:kStarCanvasLyrics]) return @"Canvas with lyrics";
    if ([key isEqualToString:kStarFill]) return @"Fill";
    if ([key isEqualToString:kStarColorful]) return @"Colourful";
    return @"Default";
}

static NSString *starViewForArtwork(SGLockArtwork artwork, BOOL canvasLyrics) {
    if (artwork == SGLockArtworkOff) return kStarDefault;
    if (artwork == SGLockArtworkEverySong) return kStarColorful;
    if (artwork == SGLockArtworkFill) return kStarFill;
    if (artwork == SGLockArtworkLyrics) return kStarCanvasLyrics;
    if (SGLockArtworkHasMotion(artwork)) return canvasLyrics ? kStarCanvasLyrics : kStarCanvas;
    return nil;
}

static SGLockArtwork artworkForStarView(NSString *view) {
    if ([view isEqualToString:kStarDefault]) return SGLockArtworkOff;
    if ([view isEqualToString:kStarColorful]) return SGLockArtworkEverySong;
    if ([view isEqualToString:kStarFill]) return SGLockArtworkFill;
    return SGLockArtworkMotion;
}

static void selectStarView(NSString *view) {
    if ([view isEqualToString:kStarDefault]) {
        SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
        SGLockScreenCanvasLyricsSetEnabled(NO);
    } else if ([view isEqualToString:kStarColorful]) {
        SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkEverySong);
        SGLockScreenCanvasLyricsSetEnabled(NO);
    } else if ([view isEqualToString:kStarFill]) {
        SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkFill);
        SGLockScreenCanvasLyricsSetEnabled(NO);
    } else if ([view isEqualToString:kStarCanvas] || [view isEqualToString:kStarCanvasLyrics]) {
        SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkMotion);
        SGLockScreenCanvasLyricsSetEnabled([view isEqualToString:kStarCanvasLyrics]);
    }
}

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
            BOOL hadSelection = store.objectForKey(SGKeyFullScreenArtwork) != nil
                || store.objectForKey(SGKeyLockScreenMotion) != nil
                || store.objectForKey(SGKeyLegacyLockScreenArtwork) != nil;
            SGMigrateKey(SGKeyLockScreenMotion, SGKeyFullScreenArtwork);
            SGMigrateKey(SGKeyLegacyLockScreenArtwork, SGKeyFullScreenArtwork);
            if (![store objectForKey:SGKeyFullScreenArtwork]) {
                SGSetInt(SGKeyFullScreenArtwork, SGFlag(SGKeyLegacyLockScreenArtwork, YES)
                         ? SGLockArtworkMotion : SGLockArtworkOff);
            }
            NSInteger stored = SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
            if (stored == SGLockArtworkLyrics) {
                SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkMotion);
                SGLockScreenCanvasLyricsSetEnabled(YES);
            }
            if (![store objectForKey:SGKeyMotionSources] && [store objectForKey:SGKeyLockScreenArtworkSources]) {
                NSArray<NSString *> *legacy = SGArtworkOrder();
                if (legacy.count) [store setObject:legacy forKey:SGKeyMotionSources];
            }
            NSArray<NSString *> *order = SGLockScreenStarViewOrder();
            if (order.count) {
                if (hadSelection) {
                    NSString *previous = starViewForArtwork((SGLockArtwork)stored,
                        stored == SGLockArtworkLyrics || SGLockScreenCanvasLyricsEnabled());
                    if (!SGHidden(SGKeyLockScreenStar) && previous && ![order.firstObject isEqualToString:previous]) {
                        NSMutableArray *reordered = [order mutableCopy];
                        [reordered removeObject:previous];
                        [reordered insertObject:previous atIndex:0];
                        [store setObject:reordered forKey:SGKeyLockScreenStarViews];
                        order = reordered;
                    }
                }
                NSString *selected = starViewForArtwork((SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff),
                    SGLockScreenCanvasLyricsEnabled());
                if (!SGHidden(SGKeyLockScreenStar) || !selected || ![order containsObject:selected])
                    selectStarView(order.firstObject);
            }
        });
        return (SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

NSArray<NSString *> *SGLockScreenStarViewOrder(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLockScreenStarViews];
    if (![stored isKindOfClass:NSArray.class]) return defaultStarViewOrder();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in (NSArray *)stored) {
        if (([key isEqual:kStarCanvas] || [key isEqual:kStarCanvasLyrics] || [key isEqual:kStarFill]
             || [key isEqual:kStarDefault] || [key isEqual:kStarColorful])
            && ![order containsObject:key]) {
            [order addObject:key];
        }
    }
    if (!SGFlag(kStarViewsMigrated, NO)) {
        if (order.count) {
            for (NSString *key in @[kStarColorful, kStarDefault]) {
                if (![order containsObject:key]) [order addObject:key];
            }
        }
        [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyLockScreenStarViews];
        SGSetEnabled(kStarViewsMigrated, YES);
    }
    if (!order.count) return defaultStarViewOrder();
    return order;
}

void SGLockScreenStarAdvanceView(void) {
    NSArray<NSString *> *order = SGLockScreenStarViewOrder();
    if (!order.count) return;
    NSString *current = starViewForArtwork(SGLockScreenArtwork(), SGLockScreenCanvasLyricsEnabled());
    NSUInteger index = current ? [order indexOfObject:current] : NSNotFound;
    NSString *next = order[index == NSNotFound ? 0 : (index + 1) % order.count];
    selectStarView(next);
    SGLog(@"lock star: switched to %@", next);
}

SGLockArtwork SGLockScreenSkipUnavailableMotion(void) {
    NSArray<NSString *> *order = SGLockScreenStarViewOrder();
    BOOL cycling = SGHidden(SGKeyLockScreenStar) && order.count > 1;
    NSString *current = starViewForArtwork(SGLockScreenArtwork(), SGLockScreenCanvasLyricsEnabled());
    NSUInteger index = current ? [order indexOfObject:current] : NSNotFound;
    for (NSUInteger step = 1; step <= order.count; step++) {
        NSString *next = order[index == NSNotFound ? step - 1 : (index + step) % order.count];
        if ([next isEqualToString:kStarCanvas] || [next isEqualToString:kStarCanvasLyrics]) continue;
        if (cycling) selectStarView(next);
        SGLog(@"lock motion: no animated source; skipped to %@", next);
        return artworkForStarView(next);
    }
    if (cycling) selectStarView(kStarDefault);
    SGLog(@"lock motion: no animated source or non-motion view is enabled; using iOS default artwork");
    return SGLockArtworkOff;
}

BOOL SGLockScreenCanvasLyricsEnabled(void) {
    BOOL canvas = SGHidden(SGKeyLockScreenCanvasLyrics);
    if (canvas && SGFlag(SGKeyLockScreenLyrics, NO) && SGEnabled(SGKeyLockScreenExclusiveLyrics)) {
        SGSetEnabled(kArtistLyricsWasEnabled, YES);
        SGSetEnabled(SGKeyLockScreenLyrics, NO);
    }
    return canvas;
}

CGFloat SGLockScreenCoverArtworkScale(void) {
    return (CGFloat)SGInt(SGKeyLockScreenCoverArtworkScale, 50) / 100.0;
}

void SGLockScreenCanvasLyricsSetEnabled(BOOL enabled) {
    SGSetEnabled(SGKeyLockScreenCanvasLyrics, enabled);
    if (enabled && SGEnabled(SGKeyLockScreenExclusiveLyrics) && SGFlag(SGKeyLockScreenLyrics, NO)) {
        SGSetEnabled(kArtistLyricsWasEnabled, YES);
        SGSetEnabled(SGKeyLockScreenLyrics, NO);
    } else if (!enabled && SGFlag(kArtistLyricsWasEnabled, NO)) {
        SGSetEnabled(SGKeyLockScreenLyrics, YES);
        SGSetEnabled(kArtistLyricsWasEnabled, NO);
    }
}

void SGLockScreenLyricsExclusivityChanged(BOOL enabled) {
    if (enabled) {
        (void)SGLockScreenCanvasLyricsEnabled();
    } else if (SGFlag(kArtistLyricsWasEnabled, NO)) {
        SGSetEnabled(SGKeyLockScreenLyrics, YES);
        SGSetEnabled(kArtistLyricsWasEnabled, NO);
    }
}

void SGLockScreenArtistLyricsChanged(BOOL enabled) {
    if (enabled && SGEnabled(SGKeyLockScreenExclusiveLyrics)) {
        SGLockScreenCanvasLyricsSetEnabled(NO);
    } else if (!enabled) {
        SGSetEnabled(kArtistLyricsWasEnabled, NO);
    }
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        SGModRow *style = SGChoiceRow(@"Lyrics style", @"Still draws each line once; Animated breathes the cover behind it",
                                      SGKeyLockScreenLyricsStyle, @[@"Still", @"Animated"], 0);
        style.visible = ^BOOL { return starViewOrderContains(kStarCanvasLyrics); };
        SGModRow *exclusiveLyrics = SGSwitchRow(@"Automatically switch lyric styles",
            @"Turn off artist-name lyrics when Canvas lyrics turn on, and vice versa", SGKeyLockScreenExclusiveLyrics);
        exclusiveLyrics.changed = ^(BOOL on) { SGLockScreenLyricsExclusivityChanged(on); };
        SGModRow *star = SGOptionRow(@"Switch with the star", @"Cycle through the ordered lock-screen artwork views",
                                     SGKeyLockScreenStar);
        star.changed = ^(BOOL on) {
            if (!on) {
                NSArray<NSString *> *order = SGLockScreenStarViewOrder();
                if (order.count) selectStarView(order.firstObject);
            }
        };
        SGModRow *starViews = SGLockScreenStarViewsRow();
        SGModRow *lowData = SGOptionRow(@"Download in Low Data Mode", @"Moving artwork, up to about 7 MB a song", SGKeyMotionLowData);
        lowData.visible = ^BOOL { return starViewOrderContains(kStarCanvas) || starViewOrderContains(kStarCanvasLyrics); };
        SGModRow *coverSize = SGSliderRow(@"Fallback album art size",
            @"Every song's colourful cover-and-blur treatment, even when Canvas or animated covers are available",
            0.25, 0.85, 0.05,
            ^double { return SGLockScreenCoverArtworkScale(); },
            ^(double value) { SGSetInt(SGKeyLockScreenCoverArtworkScale, (NSInteger)lround(value * 100)); },
            ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
        coverSize.visible = ^BOOL { return starViewOrderContains(kStarColorful); };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        return @[
            starViews,
            style,
            exclusiveLyrics,
            star,
            sources,
            lowData,
            coverSize,
        ];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

SGModRow *SGLockScreenStarViewsRow(void) {
    SGModRow *row = SGPageRow(@"Full-screen artwork", ^UIViewController *{
        NSArray<SGSource *> *views = @[
            [SGSource sourceWithKey:kStarCanvas name:@"Canvas" detail:@"The track's Canvas or its Apple Music animated cover"],
            [SGSource sourceWithKey:kStarCanvasLyrics name:@"Canvas with lyrics" detail:@"Synced lyrics over the moving artwork"],
            [SGSource sourceWithKey:kStarFill name:@"Fill" detail:@"The cover fading into progressively blurred artwork"],
            [SGSource sourceWithKey:kStarColorful name:@"Colourful" detail:@"Every Song: the custom moving-cover look, without source animations"],
            [SGSource sourceWithKey:kStarDefault name:@"Default" detail:@"iOS's full album artwork without an animated layer"],
        ];
        return SGSourcesPageMakeWithMinimumOnCount(@"Full-screen artwork",
            @"Drag to choose the order. The first available view is used when star cycling is off. Move a view below the line to disable it; keep at least one enabled.",
            views, ^NSArray<NSString *> *{ return SGLockScreenStarViewOrder(); },
            ^(NSArray<NSString *> *keys) {
                NSArray<NSString *> *order = keys.count ? keys : @[kStarDefault];
                [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyLockScreenStarViews];
                if (!SGHidden(SGKeyLockScreenStar) || ![order containsObject:starViewForArtwork(SGLockScreenArtwork(), SGLockScreenCanvasLyricsEnabled())])
                    selectStarView(order.firstObject);
            }, 1);
    });
    row.value = ^NSString * {
        NSArray<NSString *> *current = SGLockScreenStarViewOrder();
        if (!current.count) return @"Default";
        if (SGHidden(SGKeyLockScreenStar) && current.count > 1) {
            NSString *selected = starViewForArtwork(SGLockScreenArtwork(), SGLockScreenCanvasLyricsEnabled());
            NSUInteger index = selected ? [current indexOfObject:selected] : NSNotFound;
            if (index != NSNotFound)
                return [NSString stringWithFormat:@"%@ (%lu/%lu)", starViewName(selected),
                        (unsigned long)index + 1, (unsigned long)current.count];
        }
        NSString *first = starViewName(current.firstObject);
        return current.count == 1 ? first : [NSString stringWithFormat:@"%@ +%lu", first, (unsigned long)current.count - 1];
    };
    return SGWithSymbol(row, @"arrow.trianglehead.2.clockwise.rotate.90");
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(@"Full-screen artwork", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        NSString *message = [NSString stringWithFormat:@"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers and Fill can show there once the iPhone is updated.", UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Needs iOS 26" message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
