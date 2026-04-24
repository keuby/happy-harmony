import { hilog } from '@kit.PerformanceAnalysisKit';

import { AuthState, cancelLogin, startLogin } from '../service/auth/authStore';
import { Radius, Spacing } from '../common/constants/spacing';
import { getServerUrl } from '../api/serverConfig';

@Component
export struct LoginPage {
  @ObjectLink state: AuthState;
  @State debugTapCount: number = 0;

  build() {
    Column() {
      Column() {
        Text('happy')
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('HarmonyOS client')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: Spacing.xs })
      }
      .margin({ top: Spacing.xl * 2, bottom: Spacing.xl })

      if (this.state.status === 'authenticating') {
        Column() {
          Text('Waiting for approval…')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: Spacing.sm })

          Text('Open an already-signed-in happy mobile/web app and paste this URL to approve (long-press to copy):')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ bottom: Spacing.md })

          Column() {
            Text(this.state.pendingPublicKey)
              .fontSize(11)
              .fontFamily('HarmonyOS Sans Mono')
              .fontColor($r('app.color.code_text'))
              .textAlign(TextAlign.Center)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding(Spacing.md)
          .backgroundColor($r('app.color.code_bg'))
          .borderRadius(Radius.sm)
          .margin({ bottom: Spacing.lg })

          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.text_secondary'))
            .margin({ bottom: Spacing.lg })

          Button('Cancel')
            .width('100%')
            .height(44)
            .backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.text_primary'))
            .fontSize(15)
            .borderRadius(Radius.md)
            .onClick(() => {
              hilog.info(0x0000, 'loginPage', 'Cancel tapped');
              cancelLogin();
            })
        }
        .width('100%')
      } else {
        Column() {
          Text('Sign in by approving this device from another signed-in happy app (CLI, mobile, or web).')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ bottom: Spacing.lg })

          Button('Connect')
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.primary'))
            .fontColor(Color.White)
            .fontSize(16)
            .borderRadius(Radius.md)
            .onClick(() => {
              this.debugTapCount = this.debugTapCount + 1;
              hilog.info(0x0000, 'loginPage', 'Connect tapped #%{public}d', this.debugTapCount);
              startLogin();
            })

          Text(`debug taps: ${this.debugTapCount}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: Spacing.sm })

          if (this.state.lastError !== '') {
            Text(this.state.lastError)
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .margin({ top: Spacing.md })
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
      }

      Blank()

      Text(`server: ${getServerUrl()}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: Spacing.md })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Spacing.md, right: Spacing.md })
    .backgroundColor($r('app.color.background'))
    .alignItems(HorizontalAlign.Center)
  }
}
