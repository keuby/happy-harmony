import type common from '@ohos.app.ability.common';

import { AuthState, authStore, initAuth } from '../service/auth/authStore';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';

// Navigation wraps the content so Phase 2 can upgrade HomePage → a
// pushable NavDestination (session detail, settings) without restructuring
// the root. For 1a the stack stays empty and the root content dispatches
// on authStore.status.

@Entry
@Component
struct Index {
  private pageStack: NavPathStack = new NavPathStack();
  @State state: AuthState = authStore;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    void initAuth(ctx);
  }

  build() {
    Navigation(this.pageStack) {
      Column() {
        if (this.state.status === 'loading') {
          this.buildLoading()
        } else if (this.state.status === 'authenticated') {
          HomePage({ state: this.state })
        } else {
          LoginPage({ state: this.state })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }

  @Builder
  private buildLoading() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
