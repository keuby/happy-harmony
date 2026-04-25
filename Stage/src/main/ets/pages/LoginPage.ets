import { hilog } from '@kit.PerformanceAnalysisKit';

import { AuthState, cancelLogin, loginWithSecret, startLogin } from '../service/auth/authStore';
import { Radius, Spacing } from '../common/constants/spacing';
import { getServerUrl } from '../api/serverConfig';

@Component
export struct LoginPage {
  @ObjectLink state: AuthState;
  @State debugTapCount: number = 0;
  @State showSecretForm: boolean = false;
  @State secretInput: string = '';

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
        // Shared 'authenticating' state. QR approval flow populates
        // pendingPublicKey; secret-key restore leaves it empty — we
        // branch on that to pick the UI.
        if (this.state.pendingPublicKey !== '') {
          this.buildAwaitingApproval()
        } else {
          this.buildRestoring()
        }
      } else if (this.showSecretForm) {
        this.buildSecretForm()
      } else {
        this.buildEntry()
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

  @Builder
  private buildEntry() {
    Column() {
      Text('Sign in by approving this device from another signed-in happy app (CLI, mobile, or web), or restore with your account Secret Key.')
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

      Button('Restore with Secret Key')
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.text_primary'))
        .fontSize(14)
        .borderRadius(Radius.md)
        .margin({ top: Spacing.sm })
        .onClick(() => {
          this.showSecretForm = true;
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

  @Builder
  private buildSecretForm() {
    Column() {
      Text('Restore with Secret Key')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: Spacing.sm })

      Text('Open happy on a signed-in device → Settings → Account → show the Secret Key. Paste the XXXXX-XXXXX-… string below.')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: Spacing.md })

      TextArea({ placeholder: 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', text: this.secretInput })
        .width('100%')
        .height(140)
        .fontSize(13)
        .fontFamily('HarmonyOS Sans Mono')
        .fontColor($r('app.color.code_text'))
        .backgroundColor($r('app.color.code_bg'))
        .borderRadius(Radius.sm)
        .padding(Spacing.md)
        .margin({ bottom: Spacing.md })
        .onChange((value: string) => {
          this.secretInput = value;
        })

      Button('Log in')
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.primary'))
        .fontColor(Color.White)
        .fontSize(16)
        .borderRadius(Radius.md)
        .onClick(() => {
          hilog.info(0x0000, 'loginPage', 'Restore submit');
          void loginWithSecret(this.secretInput);
        })

      Button('Back')
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.text_primary'))
        .fontSize(14)
        .borderRadius(Radius.md)
        .margin({ top: Spacing.sm })
        .onClick(() => {
          this.showSecretForm = false;
          this.secretInput = '';
        })

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

  @Builder
  private buildAwaitingApproval() {
    Column() {
      Text('Waiting for approval…')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: Spacing.sm })

      Text('Scan with an already-signed-in happy mobile/web app to approve. If the scanner refuses, long-press the URL below to copy.')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: Spacing.md })

      Column() {
        QRCode(this.state.pendingPublicKey)
          .width(220)
          .height(220)
          .color($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
      }
      .padding(Spacing.md)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(Radius.sm)
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
  }

  @Builder
  private buildRestoring() {
    Column() {
      Text('Signing in…')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: Spacing.lg })

      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.text_secondary'))
    }
    .width('100%')
  }
}
