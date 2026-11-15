// 위젯 기본 배경(불투명 바탕)을 시스템이 걷어내도록 위젯 설명자를 가공한다. (비공개 API, 사이드로딩 전용)
//
// WidgetKit 내부 클래스의 getAllCurrentDescriptorsWithCompletion: 결과를 가로채서
// 이 위젯의 CHSWidgetDescriptor 를 mutableCopy 한 뒤
//   setBackgroundRemovable:YES / setTransparent:YES / setPreferredBackgroundStyle:1
// 을 지정해서 돌려준다. 시스템이 설명자를 캐시하므로 처음 적용할 때는 기기 재시작이 필요하다.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP gOriginal = NULL;
static NSString *const kWidgetKind = @"LauncherWidget";

static id ISPatchDescriptor(id desc) {
    if (![desc respondsToSelector:@selector(mutableCopy)]) return desc;
    id c = [desc mutableCopy];
    SEL sR = NSSelectorFromString(@"setBackgroundRemovable:");
    SEL sT = NSSelectorFromString(@"setTransparent:");
    SEL sS = NSSelectorFromString(@"setPreferredBackgroundStyle:");
    if (![c respondsToSelector:sR] || ![c respondsToSelector:sT] || ![c respondsToSelector:sS]) return desc;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(c, sR, YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(c, sT, YES);
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(c, sS, 1);
    return c;
}

static id ISPatchResult(id result) {
    @try {
        Ivar iv = class_getInstanceVariable(object_getClass(result), "widgetDescriptors");
        if (!iv) return result;
        void **slot = (void **)((char *)(__bridge void *)result + ivar_getOffset(iv));
        id widgets = (__bridge id)(*slot);
        if (![widgets respondsToSelector:@selector(count)] || ![widgets respondsToSelector:@selector(objectAtIndex:)]) return result;

        NSUInteger n = [widgets count];
        NSMutableArray *patched = [NSMutableArray arrayWithCapacity:n];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < n; i++) {
            id d = [widgets objectAtIndex:i];
            id kind = [d respondsToSelector:NSSelectorFromString(@"kind")] ? [d valueForKey:@"kind"] : nil;
            if ([kind isEqual:kWidgetKind]) {
                id p = ISPatchDescriptor(d);
                if (p != d) changed = YES;
                [patched addObject:p];
            } else {
                [patched addObject:d];
            }
        }
        if (changed) *slot = (void *)CFBridgingRetain([patched copy]);
    } @catch (NSException *e) {
        // 실패해도 원래 결과를 그대로 돌려준다
    }
    return result;
}

static void ISHooked(id self, SEL _cmd, void (^completion)(id)) {
    void (^wrapped)(id) = ^(id result) {
        completion(ISPatchResult(result));
    };
    ((void (*)(id, SEL, id))gOriginal)(self, _cmd, wrapped);
}

__attribute__((constructor)) static void ISInstallTransparentHook(void) {
    Class cls = NSClassFromString(@"_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject");
    SEL sel = NSSelectorFromString(@"getAllCurrentDescriptorsWithCompletion:");
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) return;
    gOriginal = method_getImplementation(m);
    method_setImplementation(m, (IMP)ISHooked);
}
