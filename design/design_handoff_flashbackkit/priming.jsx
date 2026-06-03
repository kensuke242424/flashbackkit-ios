/* priming.jsx — FlashbackKit：画面収録 許可プライミング（pre-permission）
   Exports to window: PrimingPhone, PrimingContent, COPY, SystemAlert.
   uses globals (components.jsx): CleanMark, Icon, StatusBar, window.DIRECTIONS
   Color rule honored: orange = recording/actionable, gray/slate = not-recording.
   The hero Time Slice mark is the brand-NEUTRAL slate (recording is not on yet);
   the only orange is the actionable CTA. */

(function () {
  const mono = { fontFamily: 'var(--mono)' };

  // ── Copy variants (見出し / 本文 / ヒント / CTA) ─────────────────────────
  const COPY = {
    A: {
      tag: 'A · 中立・説明型（推奨）',
      head: '画面収録をオンにします',
      body: '次に表示される iOS の確認で「許可」を選ぶと、アプリ内の直前の操作を自動で保持できます。',
      hint: 'タップすると iOS の確認が表示されます',
      cta: '許可へ進む',
      later: 'あとで',
    },
    B: {
      tag: 'B · ベネフィット・温度型',
      head: '“直前” を、のがさない',
      body: 'オンにすると、次回からアプリ内の直前の操作を自動で残します。続けて表示される iOS の確認で「許可」を選んでください。',
      hint: 'タップすると iOS の確認が表示されます',
      cta: '続ける',
      later: 'あとで',
    },
    C: {
      tag: 'C · ステップ・最小型',
      head: 'あと 1 ステップ',
      body: 'このあと表示される iOS の確認で「許可」を選ぶと、アプリ内の操作を保持します。',
      hint: '次の確認は iOS が表示します',
      cta: '確認を表示',
      later: 'キャンセル',
    },
  };

  // 3-dot step strip (optional) — ①この画面 → ②iOSで許可 → ③録画オン
  function StepStrip({ t }) {
    const steps = [
      { n: '1', label: 'この画面', on: true },
      { n: '2', label: 'iOS で許可', on: false },
      { n: '3', label: '録画オン', on: false },
    ];
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, justifyContent: 'center' }}>
        {steps.map((s, i) => (
          <React.Fragment key={s.n}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, width: 56 }}>
              <span style={{
                width: 18, height: 18, borderRadius: 9, fontSize: 10.5, fontWeight: 700,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: s.on ? t.ctrl : 'transparent', color: s.on ? t.onCtrl : t.tertiary,
                border: s.on ? 'none' : `1.5px solid ${t.separator}`,
              }}>{s.n}</span>
              <span style={{ fontSize: 9.5, color: s.on ? t.label : t.tertiary, fontWeight: s.on ? 600 : 500, whiteSpace: 'nowrap' }}>{s.label}</span>
            </div>
            {i < 2 && <div style={{ flex: '0 0 14px', height: 1.5, background: t.separator, marginBottom: 14 }} />}
          </React.Fragment>
        ))}
      </div>
    );
  }

  // ── The priming content block (mark + heading + body + hint + CTAs) ─────
  // buttons: 'single' (filled CTA + text あとで) | 'double' (あとで outline + CTA filled)
  function PrimingContent({ d, scheme, copy, buttons = 'single', showSteps = false, markSize = 52, compact = false }) {
    const t = d[scheme];
    const cta = copy.cta, later = copy.later;
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', width: '100%' }}>
        {/* hero Time Slice mark — NEUTRAL slate (not recording yet) */}
        <div style={{ width: markSize, height: markSize, marginBottom: compact ? 12 : 16 }}>
          <CleanMark ring={t.accent} wedge={t.accent} wedgeOpacity={0.45} hub={t.accent} size={markSize} sw={3.4} />
        </div>

        <div style={{ fontSize: compact ? 17 : 19, fontWeight: 700, color: t.label, letterSpacing: '-0.01em', lineHeight: 1.25 }}>{copy.head}</div>

        <div style={{ fontSize: 13.5, color: t.secondary, lineHeight: 1.6, marginTop: 9, maxWidth: 250, textWrap: 'pretty' }}>{copy.body}</div>

        {showSteps && (
          <div style={{ marginTop: 18, width: '100%' }}>
            <StepStrip t={t} />
          </div>
        )}

        {/* CTAs */}
        <div style={{ marginTop: compact ? 18 : 24, width: '100%', display: 'flex', flexDirection: 'column', gap: 10 }}>
          {buttons === 'double' ? (
            <div style={{ display: 'flex', gap: 10 }}>
              <button style={{
                flex: 1, height: 48, borderRadius: 12, border: `1px solid ${t.separator}`, background: 'transparent',
                color: t.label, fontSize: 16, fontWeight: 600, fontFamily: 'var(--sf)', cursor: 'pointer',
              }}>{later}</button>
              <button style={{
                flex: 1.4, height: 48, borderRadius: 12, border: 'none', background: t.ctrl,
                color: t.onCtrl, fontSize: 16, fontWeight: 600, fontFamily: 'var(--sf)', cursor: 'pointer',
              }}>{cta}</button>
            </div>
          ) : (
            <>
              <button style={{
                width: '100%', height: 50, borderRadius: 12, border: 'none', background: t.ctrl,
                color: t.onCtrl, fontSize: 16, fontWeight: 600, fontFamily: 'var(--sf)', cursor: 'pointer',
              }}>{cta}</button>
              <button style={{
                width: '100%', height: 28, border: 'none', background: 'transparent',
                color: t.secondary, fontSize: 15, fontWeight: 500, fontFamily: 'var(--sf)', cursor: 'pointer',
              }}>{later}</button>
            </>
          )}
        </div>

        {/* the priming hint — sets the expectation that the NEXT tap triggers the OS dialog */}
        {copy.hint && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 12, color: t.tertiary }}>
            <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke={t.tertiary} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="8" cy="8" r="6.2" /><path d="M8 7.4v3.4" /><circle cx="8" cy="5.2" r="0.5" fill={t.tertiary} stroke="none" /></svg>
            <span style={{ fontSize: 11, color: t.tertiary, ...mono }}>{copy.hint}</span>
          </div>
        )}
      </div>
    );
  }

  // ── A faithful-ish iOS system alert (OS-controlled, NOT customizable) ───
  function SystemAlert({ scheme = 'light', appName = 'DemoApp' }) {
    const dark = scheme === 'dark';
    const panel = dark ? 'rgba(44,44,46,0.96)' : 'rgba(248,248,248,0.96)';
    const ink = dark ? '#fff' : '#000';
    const sub = dark ? '#98989F' : '#3c3c43';
    const sep = dark ? 'rgba(255,255,255,0.12)' : 'rgba(60,60,67,0.18)';
    const blue = dark ? '#0A84FF' : '#007AFF';
    return (
      <div style={{ width: 240, borderRadius: 14, background: panel, backdropFilter: 'blur(20px)', overflow: 'hidden', boxShadow: '0 8px 30px rgba(0,0,0,0.28)' }}>
        <div style={{ padding: '17px 16px 14px', textAlign: 'center' }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: ink, lineHeight: 1.3 }}>“{appName}”が画面の<br />ブロードキャストを開始します</div>
          <div style={{ fontSize: 12, color: sub, lineHeight: 1.4, marginTop: 5 }}>この App での録画が開始されます。</div>
        </div>
        <div style={{ borderTop: `0.5px solid ${sep}`, display: 'flex' }}>
          <div style={{ flex: 1, padding: '11px 0', textAlign: 'center', fontSize: 16, color: blue, borderRight: `0.5px solid ${sep}` }}>キャンセル</div>
          <div style={{ flex: 1, padding: '11px 0', textAlign: 'center', fontSize: 16, fontWeight: 600, color: blue }}>収録を開始</div>
        </div>
      </div>
    );
  }

  // ── Dimmed dormant ReportView backdrop (sits behind the sheet) ──────────
  function DormantBackdrop({ t, scheme }) {
    return (
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <StatusBar t={t} />
        <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 16px', position: 'relative' }}>
          <span style={{ color: t.ctrl }}><Icon name="close" size={22} sw={2} /></span>
          <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 16, fontWeight: 600, color: t.label, fontFamily: 'var(--sf)' }}>Flashback</span>
          <span style={{ marginLeft: 'auto', color: t.ctrl }}><Icon name="gear" size={21} sw={1.7} /></span>
        </div>
        <div style={{ flex: 1, padding: '4px 16px 0' }}>
          <div style={{ height: 168, borderRadius: 14, background: t.fieldBg, border: `1px dashed ${t.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, marginTop: 4 }}>
            <CleanMark ring={t.tertiary} wedge={t.secondary} wedgeOpacity={0.55} hub={t.tertiary} size={40} sw={3.4} />
            <span style={{ fontSize: 13, fontWeight: 600, color: t.secondary }}>録画はオフです</span>
          </div>
        </div>
      </div>
    );
  }

  // ── Device shell ─────────────────────────────────────────────────────
  function Bezel({ scheme, children }) {
    return (
      <div style={{ width: 286, height: 600, position: 'relative' }}>
        <div style={{
          position: 'absolute', inset: 0, borderRadius: 42, background: scheme === 'light' ? '#dcdce0' : '#000',
          padding: 5, boxShadow: scheme === 'light' ? '0 10px 30px rgba(0,0,0,0.14), 0 1px 0 rgba(255,255,255,0.6) inset' : '0 10px 30px rgba(0,0,0,0.5)',
        }}>
          <div style={{ width: '100%', height: '100%', borderRadius: 37, overflow: 'hidden', position: 'relative' }}>
            {children}
          </div>
        </div>
      </div>
    );
  }

  function HomeBar({ t }) {
    return (
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 22, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 7 }}>
        <div style={{ width: 110, height: 4.5, borderRadius: 3, background: t.label, opacity: 0.85 }} />
      </div>
    );
  }

  // ── PrimingPhone — format: 'sheet' | 'full' | 'state' ───────────────────
  function PrimingPhone({ d, scheme = 'light', format = 'sheet', variant = 'A', buttons = 'single', showSteps = false }) {
    const t = d[scheme];
    const copy = COPY[variant];

    if (format === 'sheet') {
      const sheetBg = scheme === 'dark' ? '#1C1C1E' : '#FFFFFF';
      const sheetH = showSteps ? 446 : 372;
      return (
        <Bezel scheme={scheme}>
          <div style={{ position: 'absolute', inset: 0, background: t.bg }} />
          {/* dimmed dormant ReportView behind */}
          <div style={{ position: 'absolute', inset: 0, opacity: scheme === 'dark' ? 0.5 : 0.6 }}>
            <DormantBackdrop t={t} scheme={scheme} />
          </div>
          {/* scrim */}
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.34)' }} />
          {/* sheet (.medium detent) */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: sheetH, background: sheetBg, borderRadius: '20px 20px 0 0', boxShadow: '0 -8px 30px rgba(0,0,0,0.3)', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
              <div style={{ width: 36, height: 5, borderRadius: 3, background: t.tertiary, opacity: 0.6 }} />
            </div>
            <div style={{ flex: 1, padding: '20px 24px 0', display: 'flex', flexDirection: 'column', justifyContent: 'flex-start' }}>
              <PrimingContent d={d} scheme={scheme} copy={copy} buttons={buttons} showSteps={showSteps} compact={true} markSize={46} />
            </div>
          </div>
          <div style={{ position: 'absolute', top: 0, left: 0, right: 0 }}><StatusBar t={{ label: t.label }} /></div>
        </Bezel>
      );
    }

    if (format === 'full') {
      return (
        <Bezel scheme={scheme}>
          <div style={{ position: 'absolute', inset: 0, background: t.bg, display: 'flex', flexDirection: 'column' }}>
            <StatusBar t={t} />
            {/* nav: × only (cancel) */}
            <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
              <span style={{ color: t.ctrl }}><Icon name="close" size={22} sw={2} /></span>
            </div>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 24px 40px' }}>
              <PrimingContent d={d} scheme={scheme} copy={copy} buttons={buttons} showSteps={showSteps} markSize={60} />
            </div>
            <HomeBar t={t} />
          </div>
        </Bezel>
      );
    }

    // format === 'state' — a sibling state inside the full-screen ReportView
    return (
      <Bezel scheme={scheme}>
        <div style={{ position: 'absolute', inset: 0, background: t.bg, display: 'flex', flexDirection: 'column' }}>
          <StatusBar t={t} />
          <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 16px', position: 'relative' }}>
            <span style={{ color: t.ctrl }}><Icon name="close" size={22} sw={2} /></span>
            <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 16, fontWeight: 600, color: t.label, fontFamily: 'var(--sf)' }}>Flashback</span>
            <span style={{ marginLeft: 'auto', color: t.ctrl }}><Icon name="gear" size={21} sw={1.7} /></span>
          </div>
          <div style={{ flex: 1, padding: '4px 16px 0', display: 'flex', flexDirection: 'column' }}>
            {/* framed hero — matches dormant/justEnabled box treatment */}
            <div style={{ height: 168, borderRadius: 14, background: t.fieldBg, border: `1px dashed ${t.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, marginTop: 4 }}>
              <CleanMark ring={t.accent} wedge={t.accent} wedgeOpacity={0.45} hub={t.accent} size={40} sw={3.4} />
              <span style={{ fontSize: 13, fontWeight: 600, color: t.label }}>{copy.head}</span>
            </div>
            <div style={{ fontSize: 12.5, color: t.secondary, lineHeight: 1.55, marginTop: 12, textWrap: 'pretty' }}>{copy.body}</div>
            {/* orange CTA row — same affordance language as dormant's 録画をオンにする */}
            <div style={{ marginTop: 16 }}>
              <button style={{ width: '100%', height: 48, borderRadius: 12, border: 'none', background: t.ctrl, color: t.onCtrl, fontSize: 15, fontWeight: 600, fontFamily: 'var(--sf)', cursor: 'pointer' }}>{copy.cta}</button>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, marginTop: 10, color: t.tertiary }}>
              <span style={{ fontSize: 11, color: t.tertiary, ...mono }}>{copy.hint}</span>
            </div>
            {/* 環境情報 — keeps continuity with the other ReportView states */}
            <div style={{ marginTop: 22 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: t.tertiary, letterSpacing: '0.02em', marginBottom: 6 }}>環境情報</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
                {[['iphone', 'iPhone 16'], ['gear', 'iOS 18.4'], ['app', 'v1.0 (1)']].map(([ic, tx]) => (
                  <div key={tx} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ color: t.secondary, display: 'flex', width: 16 }}><Icon name={ic} size={15} sw={1.4} color={t.secondary} /></span>
                    <span style={{ fontSize: 13, color: t.secondary, fontFamily: 'var(--sf)' }}>{tx}</span>
                  </div>
                ))}
              </div>
            </div>
            <div style={{ flex: 1 }} />
          </div>
          <HomeBar t={t} />
        </div>
      </Bezel>
    );
  }

  // ── SettingsTimingPhone — 設定画面に「アプリ起動時に権限を確認する」トグルを追加 ──
  // iOS 標準色（トグル＝緑 / ステータス＝緑/赤）。既存 PhoneSettingsView の語彙に準拠。
  // on: false（既定・起動時は確認しない）| true（起動直後に即 OS 確認）
  // ReplayKit の画面収録は iOS 設定に権限トグルが無いため「iOS の設定を開く」導線は置かない。
  function SettingsTimingPhone({ d, scheme = 'light', on = false }) {
    const t = d[scheme];
    const dark = scheme === 'dark';
    const page = dark ? '#000' : '#F2F2F7';
    const cell = dark ? '#1C1C1E' : '#FFFFFF';
    const sep = dark ? '#38383A' : '#E3E3E8';
    const sysBlue = dark ? '#0A84FF' : '#007AFF';
    const sysGreen = dark ? '#30D158' : '#34C759';
    const SecHead = ({ children }) => <div style={{ fontSize: 12, color: t.secondary, padding: '0 16px 6px', letterSpacing: '0.02em' }}>{children}</div>;
    const Foot = ({ children }) => <div style={{ fontSize: 11, color: t.secondary, padding: '7px 16px 0', lineHeight: 1.45 }}>{children}</div>;
    const Switch = ({ checked, color }) => (
      <div style={{ width: 40, height: 24, borderRadius: 12, background: checked ? color : (dark ? 'rgba(120,120,128,0.32)' : '#E3E3E8'), position: 'relative', flex: '0 0 auto' }}>
        <div style={{ position: 'absolute', top: 2, left: checked ? 18 : 2, width: 20, height: 20, borderRadius: 10, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)' }} />
      </div>
    );
    return (
      <div style={{ width: 286, height: 600, position: 'relative' }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: 42, background: dark ? '#000' : '#dcdce0', padding: 5, boxShadow: dark ? '0 10px 30px rgba(0,0,0,0.5)' : '0 10px 30px rgba(0,0,0,0.14), 0 1px 0 rgba(255,255,255,0.6) inset' }}>
          <div style={{ width: '100%', height: '100%', borderRadius: 37, background: page, overflow: 'hidden', position: 'relative', display: 'flex', flexDirection: 'column' }}>
            <StatusBar t={t} />
            <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 12px', position: 'relative' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 2, color: sysBlue, fontSize: 16 }}>
                <svg width="11" height="18" viewBox="0 0 11 18" fill="none" stroke={sysBlue} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M9 2L3 9l6 7" /></svg>
                <span style={{ fontWeight: 400 }}>レポート</span>
              </span>
              <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 16, fontWeight: 600, color: t.label, fontFamily: 'var(--sf)' }}>設定</span>
            </div>

            <div style={{ flex: 1, padding: '8px 0', overflow: 'hidden' }}>
              {/* NEW — 起動時の権限確認トグル */}
              <SecHead>画面収録の権限</SecHead>
              <div style={{ margin: '0 16px', background: cell, borderRadius: 11, overflow: 'hidden' }}>
                <div style={{ display: 'flex', alignItems: 'center', padding: '11px 14px', gap: 12 }}>
                  <span style={{ fontSize: 15, color: t.label, flex: 1, lineHeight: 1.3 }}>アプリ起動時に権限を確認する</span>
                  <Switch checked={on} color={sysGreen} />
                </div>
              </div>
              <Foot>オンにすると、アプリの起動直後に画面収録の許可を確認します。オフのときは、「録画をオンにする」を押したときだけ確認します。</Foot>

              {/* 録画（権限ステータス）— 読み取り専用 */}
              <div style={{ height: 22 }} />
              <SecHead>ステータス</SecHead>
              <div style={{ margin: '0 16px', background: cell, borderRadius: 11, overflow: 'hidden' }}>
                <div style={{ display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12 }}>
                  <span style={{ fontSize: 15, color: t.label, flex: 1 }}>録画の状態</span>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 14, color: on ? sysGreen : t.secondary, fontWeight: 500 }}>
                    <span style={{ width: 7, height: 7, borderRadius: 4, background: on ? sysGreen : t.tertiary }} />
                    {on ? '確認待ち' : 'オフ'}
                  </span>
                </div>
              </div>
              <Foot>許可の確認は「録画をオンにする」操作時に表示されます。許可するとクリップの保持が始まります。</Foot>
            </div>

            <div style={{ height: 22, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 7 }}>
              <div style={{ width: 110, height: 4.5, borderRadius: 3, background: t.label, opacity: 0.85 }} />
            </div>
          </div>
        </div>
      </div>
    );
  }

  Object.assign(window, { PrimingPhone, PrimingContent, COPY, SystemAlert, SettingsTimingPhone });
})();
