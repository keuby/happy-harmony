import { hilog } from '@kit.PerformanceAnalysisKit';

import { Session } from 'happy-wire';

import { AuthState, logout } from '../service/auth/authStore';
import { fetchSessions } from '../service/session/sessionList';
import { Radius, Spacing } from '../common/constants/spacing';

@Component
export struct HomePage {
  @ObjectLink state: AuthState;
  @State sessions: Session[] = [];
  @State loadError: string = '';
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.loading = true;
    this.loadError = '';
    const run = async (): Promise<void> => {
      try {
        const list = await fetchSessions();
        this.sessions = list;
        hilog.info(0x0000, 'homePage', 'fetched %{public}d sessions', list.length);
      } catch (e) {
        this.loadError = `load failed: ${JSON.stringify(e)}`;
        hilog.error(0x0000, 'homePage', 'fetchSessions error: %{public}s', JSON.stringify(e));
      } finally {
        this.loading = false;
      }
    };
    void run();
  }

  build() {
    Column() {
      Row() {
        Text('Sessions')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.sessions.length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ top: Spacing.xl, bottom: Spacing.md })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.text_secondary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else if (this.loadError !== '') {
        Text(this.loadError)
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(Spacing.md)
      } else if (this.sessions.length === 0) {
        Text('No sessions yet.')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Spacing.xl })
      } else {
        List({ space: 0 }) {
          ForEach(this.sessions, (s: Session) => {
            ListItem() {
              Row() {
                Column() {}
                  .width(8)
                  .height(8)
                  .backgroundColor(s.active ? $r('app.color.primary') : $r('app.color.divider'))
                  .borderRadius(4)
                  .margin({ right: Spacing.sm, top: 6 })

                Column() {
                  Text(truncateId(s.id))
                    .fontSize(13)
                    .fontFamily('HarmonyOS Sans Mono')
                    .fontColor($r('app.color.text_primary'))
                  Text('metadata pending')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                  Text(formatTime(s.updatedAt))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: Spacing.sm, bottom: Spacing.sm })
              .alignItems(VerticalAlign.Top)
            }
          }, (s: Session) => s.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.divider') })
      }

      Button('Sign out')
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.danger'))
        .fontColor(Color.White)
        .fontSize(15)
        .borderRadius(Radius.md)
        .margin({ top: Spacing.sm, bottom: Spacing.md })
        .onClick(() => {
          void logout();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Spacing.md, right: Spacing.md })
    .backgroundColor($r('app.color.background'))
    .alignItems(HorizontalAlign.Start)
  }
}

function truncateId(s: string): string {
  if (s.length <= 20) return s;
  return `${s.substring(0, 10)}…${s.substring(s.length - 6)}`;
}

function formatTime(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
