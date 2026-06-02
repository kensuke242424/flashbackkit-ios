/* components.jsx — FlashbackKit Phase 1 shared atoms
   Exports to window: LogoMark, Wordmark, PhoneReportView, TriggerToast,
   PaletteRow, SwatchStrip, Icon.
   All visuals are native-implementable (SF Pro / SF Pro Rounded / SF Mono,
   simple shapes, SF-Symbol-like glyphs) per the SwiftUI iOS16+ constraint. */

// ── SF-Symbol-ish glyphs (simple strokes only) ─────────────────────────
function Icon({ name, size = 15, color = 'currentColor', sw = 1.6 }) {
  const p = {
    width: size, height: size, viewBox: '0 0 20 20', fill: 'none',
    stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round'
  };
  switch (name) {
    case 'close': // xmark
      return <svg {...p}><path d="M5 5l10 10M15 5L5 15" /></svg>;
    case 'share': // square.and.arrow.up
      return (
        <svg {...p}>
          <path d="M10 13V3.2M10 3.2L6.8 6.4M10 3.2l3.2 3.2" />
          <path d="M5.4 9.2H4.2v7.2h11.6V9.2h-1.2" />
        </svg>);

    case 'play': // play.fill
      return <svg width={size} height={size} viewBox="0 0 20 20" fill={color}><path d="M6.5 4.6c0-.5.5-.8 1-.6l8 5.1c.4.3.4.9 0 1.2l-8 5.1c-.5.3-1 0-1-.6z" /></svg>;
    case 'scissors':
      return <svg {...p}><circle cx="5" cy="5" r="2.2" /><circle cx="5" cy="15" r="2.2" /><path d="M6.8 6.5L17 14M6.8 13.5L17 6" /></svg>;
    case 'iphone':
      return <svg {...p}><rect x="6" y="2.5" width="8" height="15" rx="2" /><path d="M8.8 4.4h2.4" /></svg>;
    case 'gear': {
      const teeth = [0, 45, 90, 135, 180, 225, 270, 315].map((deg, i) => {
        const a = deg * Math.PI / 180;
        return <line key={i} x1={(10 + 5.4 * Math.cos(a)).toFixed(2)} y1={(10 + 5.4 * Math.sin(a)).toFixed(2)} x2={(10 + 8.8 * Math.cos(a)).toFixed(2)} y2={(10 + 8.8 * Math.sin(a)).toFixed(2)} />;
      });
      return <svg {...p}>{teeth}<circle cx="10" cy="10" r="5.6" /><circle cx="10" cy="10" r="2.1" /></svg>;
    }
    case 'app':
      return <svg {...p}><rect x="3.5" y="3.5" width="13" height="13" rx="3.4" /><circle cx="14" cy="6" r="1.4" fill={color} stroke="none" /></svg>;
    case 'check':
      return <svg {...p}><path d="M4.5 10.5l3.5 3.5 7.5-8" /></svg>;
    case 'bug': // restrained ladybug / capsule body + legs (geometric)
      return (
        <svg width={size} height={size} viewBox="0 0 20 20" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round">
          <ellipse cx="10" cy="11" rx="4.6" ry="5.2" fill={color} stroke="none" />
          <path d="M10 5.8v10.4" stroke="#fff" strokeWidth="0.9" opacity="0.6" />
          <path d="M4.4 8l-2.4-1.4M15.6 8l2.4-1.4M4.2 12h-2.6M15.8 12h2.6M4.6 15.6l-2 1.6M15.4 15.6l2 1.6" />
          <path d="M7.4 5.2l-1.2-1.8M12.6 5.2l1.2-1.8" />
        </svg>);

    default:
      return null;
  }
}

// ── Unified mark: Time Slice "Clean" (clock + captured-N-seconds wedge) ──
const _tsP = (r, cd) => {const a = (cd - 90) * Math.PI / 180;return [32 + r * Math.cos(a), 32 + r * Math.sin(a)];};
const _tsWedge = (r, W) => {const [x0, y0] = _tsP(r, -W),[x1, y1] = _tsP(r, 0);return `M32 32 L${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 0 1 ${x1.toFixed(2)} ${y1.toFixed(2)} Z`;};

function CleanMark({ ring, wedge, hub, wedgeOpacity = 1, size = 44, sw = 3.2, W = 66 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none">
      <circle cx="32" cy="32" r="20" stroke={ring} strokeWidth={sw} />
      <path d={_tsWedge(20, W)} fill={wedge} fillOpacity={wedgeOpacity} />
      <circle cx="32" cy="32" r="2.6" fill={hub} />
    </svg>);

}

// LogoMark — the single brand mark, tinted per direction (ring=label, wedge=accent).
function LogoMark({ d, scheme = 'light', size = 44 }) {
  const t = d[scheme];
  // wedge ("captured slice") wears the action/control accent (orange for Quiet)
  return <CleanMark ring={t.label} wedge={t.ctrl || t.accent} hub={t.label} size={size} />;
}

function Wordmark({ d, scheme = 'light', size = 22 }) {
  const t = d[scheme];
  const rounded = d.key === 'B';
  return (
    <span style={{
      fontFamily: d.displayFont, fontWeight: 700, fontSize: size,
      letterSpacing: rounded ? '-0.01em' : '-0.02em', color: t.label,
      lineHeight: 1, whiteSpace: 'nowrap'
    }}>
      Flashback<span style={{ color: t.ctrl || t.accent, fontWeight: rounded ? 700 : 600 }}>Kit</span>
    </span>);

}

// ── Palette swatch strip ───────────────────────────────────────────────
function SwatchStrip({ items, labelColor }) {
  return (
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
      {items.map((s) =>
      <div key={s.name} style={{ display: 'flex', flexDirection: 'column', gap: 5, width: 84 }}>
          <div style={{
          height: 40, borderRadius: 8, background: s.c,
          boxShadow: 'inset 0 0 0 1px rgba(128,128,128,0.18)'
        }} />
          <div style={{ lineHeight: 1.25 }}>
            <div style={{ fontSize: 10.5, fontWeight: 600, color: labelColor }}>{s.name}</div>
            <div style={{ fontSize: 9.5, fontFamily: 'var(--mono)', color: labelColor, opacity: 0.6 }}>{s.c}</div>
          </div>
        </div>
      )}
    </div>);

}

// ── Status bar bits ─────────────────────────────────────────────────────
function StatusBar({ t }) {
  return (
    <div style={{ height: 32, display: 'flex', alignItems: 'center', padding: '0 22px', position: 'relative' }}>
      <span style={{ fontSize: 13, fontWeight: 600, color: t.label, fontVariantNumeric: 'tabular-nums' }}>9:41</span>
      <div style={{ position: 'absolute', left: '50%', top: 7, transform: 'translateX(-50%)', width: 64, height: 17, background: '#000', borderRadius: 12 }} />
      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 5 }}>
        <svg width="16" height="11" viewBox="0 0 16 11" fill={t.label}><rect x="0" y="7" width="2.6" height="4" rx="0.6" /><rect x="3.6" y="5" width="2.6" height="6" rx="0.6" /><rect x="7.2" y="2.6" width="2.6" height="8.4" rx="0.6" /><rect x="10.8" y="0" width="2.6" height="11" rx="0.6" /></svg>
        <svg width="22" height="11" viewBox="0 0 22 11" fill="none"><rect x="0.5" y="0.6" width="18" height="9.8" rx="2.6" stroke={t.label} strokeOpacity="0.4" /><rect x="2" y="2.1" width="14" height="6.8" rx="1.4" fill={t.label} /><rect x="19.4" y="3.4" width="1.6" height="4.2" rx="0.8" fill={t.label} fillOpacity="0.4" /></svg>
      </div>
    </div>);

}

// ── The core ReportView preview, parametric on direction + scheme ───────
function PhoneReportView({ d, scheme = 'light', empty = false, justEnabled = false }) {
  const t = d[scheme];
  const W = 286,H = 600;
  // grayscale filmstrip frames (refined — neutral, so accent handles read)
  const frames = Array.from({ length: 12 }, (_, i) => {
    const l = scheme === 'light' ? 0.66 + i * 37 % 22 / 100 : 0.30 + i * 37 % 22 / 100;
    return `oklch(${l} 0.012 250)`;
  });
  return (
    <div style={{ width: W, height: H, position: 'relative' }}>
      {/* device bezel */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: 42, background: scheme === 'light' ? '#dcdce0' : '#000',
        padding: 5, boxShadow: scheme === 'light' ? '0 10px 30px rgba(0,0,0,0.14), 0 1px 0 rgba(255,255,255,0.6) inset' : '0 10px 30px rgba(0,0,0,0.5)'
      }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 37, background: t.bg, overflow: 'hidden', position: 'relative', display: 'flex', flexDirection: 'column' }}>
          <StatusBar t={t} />

          {/* nav bar */}
          <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 16px', position: 'relative' }}>
            <span style={{ color: t.ctrl }}><Icon name="close" size={22} sw={2} /></span>
            <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 16, fontWeight: 600, color: t.label, fontFamily: d.displayFont }}>Flashback</span>
            <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 16, color: t.ctrl }}>
              {empty ? null : <Icon name="share" size={20} sw={1.7} />}
              <Icon name="gear" size={21} sw={1.7} />
            </span>
          </div>

          {/* body */}
          <div style={{ flex: 1, padding: '4px 16px 0', display: 'flex', flexDirection: 'column' }}>
            {empty ?
            justEnabled ?
            <>
              <div style={{ flex: '0 0 auto', height: 168, borderRadius: 14, background: t.fieldBg, border: `1px dashed ${t.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, marginTop: 4 }}>
                <div style={{ position: 'relative', width: 40, height: 40 }}>
                  <CleanMark ring={t.ctrl} wedge={t.ctrl} wedgeOpacity={1} hub={t.ctrl} size={40} sw={3.4} />
                </div>
                <span style={{ fontSize: 13, fontWeight: 600, color: t.label }}>録画をオンにしました</span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '3px 9px', borderRadius: 11, background: scheme === 'light' ? 'rgba(217,130,28,0.12)' : 'rgba(232,162,62,0.16)' }}>
                  <span style={{ width: 6, height: 6, borderRadius: 3, background: t.ctrl, display: 'inline-block' }} />
                  <span style={{ fontSize: 11, fontWeight: 600, color: t.ctrl }}>録画中</span>
                </span>
              </div>
              <div style={{ fontSize: 12.5, color: t.secondary, lineHeight: 1.5, marginTop: 12 }}>次回の起動操作から、直前の操作を自動で保持します。</div>
            </> :
            <>
              <div style={{ flex: '0 0 auto', height: 168, borderRadius: 14, background: t.fieldBg, border: `1px dashed ${t.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, marginTop: 4 }}>
                <div style={{ position: 'relative', width: 40, height: 40 }}>
                  <CleanMark ring={t.tertiary} wedge={t.secondary} wedgeOpacity={0.55} hub={t.tertiary} size={40} sw={3.4} />
                </div>
                <span style={{ fontSize: 13, fontWeight: 600, color: t.secondary }}>録画はオフです</span>
              </div>
              <div style={{ fontSize: 12.5, color: t.secondary, lineHeight: 1.5, marginTop: 12 }}>オンにすると、次回から直前の画面録画を自動で保持します。</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 11, color: t.ctrl }}>
                <CleanMark ring={t.ctrl} wedge={t.ctrl} wedgeOpacity={0.5} hub={t.ctrl} size={16} sw={3.4} />
                <span style={{ fontSize: 14, fontWeight: 600 }}>録画をオンにする</span>
              </div>
            </> :

            <>
                {/* video preview — real aspect, no letterbox */}
                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  <div style={{
                  width: 110, height: 196, borderRadius: 14, position: 'relative', overflow: 'hidden',
                  background: `repeating-linear-gradient(135deg, ${t.fieldBg}, ${t.fieldBg} 7px, ${t.separator} 7px, ${t.separator} 8px)`,
                  boxShadow: `inset 0 0 0 1px ${t.separator}`
                }}>
                    <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 6 }}>
                      <div style={{ width: 30, height: 30, borderRadius: 15, background: 'rgba(0,0,0,0.35)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <span style={{ color: '#fff', marginLeft: 2 }}><Icon name="play" size={14} /></span>
                      </div>
                      <span style={{ fontSize: 9, fontFamily: 'var(--mono)', color: t.tertiary }}>screen&nbsp;recording</span>
                    </div>
                  </div>
                </div>

                {/* play + range */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 12 }}>
                  <div style={{ width: 30, height: 30, borderRadius: 15, background: t.ctrl, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <span style={{ color: t.onCtrl, marginLeft: 2 }}><Icon name="play" size={13} /></span>
                  </div>
                  <span style={{ fontSize: 13, color: t.secondary, fontFamily: 'var(--mono)', fontVariantNumeric: 'tabular-nums' }}>0:00 ~ 0:12&nbsp;&nbsp;(0:12)</span>
                </div>

                {/* filmstrip + trim handles */}
                <div style={{ marginTop: 12, position: 'relative', height: 46 }}>
                  <div style={{ position: 'absolute', inset: '0 14px', borderRadius: 7, overflow: 'hidden', display: 'flex' }}>
                    {frames.map((c, i) => <div key={i} style={{ flex: 1, background: c }} />)}
                  </div>
                  {/* selection */}
                  <div style={{ position: 'absolute', left: 8, right: 8, top: 0, bottom: 0, borderRadius: 9, border: `2.5px solid ${t.ctrl}`, boxShadow: `0 0 0 2px ${t.bg}` }} />
                  {/* handles */}
                  {[8, null].map((l, i) =>
                <div key={i} style={{ position: 'absolute', [i === 0 ? 'left' : 'right']: 0, top: 0, bottom: 0, width: 14, background: t.ctrl, borderRadius: i === 0 ? '9px 0 0 9px' : '0 9px 9px 0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <div style={{ width: 2.5, height: 16, borderRadius: 2, background: t.onCtrl, opacity: 0.85 }} />
                    </div>
                )}
                  {/* playhead */}
                  <div style={{ position: 'absolute', left: '38%', top: -2, bottom: -2, width: 2, background: t.label, borderRadius: 2 }} />
                </div>
              </>
            }

            {/* title — クリップがあるときのみ（録画OFF時は共有導線が無いため省略） */}
            {!empty &&
            <div style={{ marginTop: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: t.label, fontFamily: d.displayFont, marginBottom: 7 }}>タイトル</div>
              <div style={{ height: 38, borderRadius: 10, background: t.fieldBg, border: `1px solid ${t.separator}`, display: 'flex', alignItems: 'center', padding: '0 12px' }}>
                <span style={{ fontSize: 14, color: t.tertiary }}>タイトルを入力</span>
              </div>
            </div>
            }

            {/* device info — quiet, unframed */}
            <div style={{ marginTop: 16 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: t.tertiary, letterSpacing: '0.02em', marginBottom: 6 }}>環境情報</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
                {[['iphone', 'iPhone 16'], ['gear', 'iOS 18.4'], ['app', 'v1.0 (1)']].map(([ic, tx]) =>
                <div key={tx} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ color: t.secondary, display: 'flex', width: 16 }}><Icon name={ic} size={15} sw={1.4} color={t.secondary} /></span>
                    <span style={{ fontSize: 13, color: t.secondary, fontFamily: d.key === 'C' ? d.displayFont : 'var(--mono)' }}>{tx}</span>
                  </div>
                )}
              </div>
            </div>
            <div style={{ flex: 1 }} />
          </div>

          {/* home indicator */}
          <div style={{ height: 22, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 7 }}>
            <div style={{ width: 110, height: 4.5, borderRadius: 3, background: t.label, opacity: 0.85 }} />
          </div>
        </div>
      </div>
    </div>);

}

// ── Settings screen (reached via the gear in ReportView nav) ────────────
function Switch({ on, color }) {
  return (
    <div style={{ width: 40, height: 24, borderRadius: 12, background: on ? color : 'rgba(120,120,128,0.32)', position: 'relative', transition: 'background .2s', flex: '0 0 auto' }}>
      <div style={{ position: 'absolute', top: 2, left: on ? 18 : 2, width: 20, height: 20, borderRadius: 10, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)', transition: 'left .2s' }} />
    </div>);

}

function PhoneSettingsView({ d, scheme = 'light', seconds = 20, showButton = true, granted = true }) {
  const t = d[scheme];
  const dark = scheme === 'dark';
  const W = 286,H = 738;
  const page = dark ? '#000' : '#F2F2F7';
  const cell = dark ? '#1C1C1E' : '#FFFFFF';
  const sep = dark ? '#38383A' : '#E3E3E8';
  // 設定画面は iOS 標準色（トグル＝緑 / ナビ・リンク・選択＝青）
  const sysBlue = dark ? '#0A84FF' : '#007AFF';
  const sysGreen = dark ? '#30D158' : '#34C759';
  const SecHead = ({ children }) => <div style={{ fontSize: 12, color: t.secondary, padding: '0 16px 6px', letterSpacing: '0.02em' }}>{children}</div>;
  const Foot = ({ children }) => <div style={{ fontSize: 11, color: t.secondary, padding: '7px 16px 0', lineHeight: 1.45 }}>{children}</div>;
  const opts = [10, 20, 30, 60];
  return (
    <div style={{ width: W, height: H, position: 'relative' }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: 42, background: dark ? '#000' : '#dcdce0', padding: 5, boxShadow: dark ? '0 10px 30px rgba(0,0,0,0.5)' : '0 10px 30px rgba(0,0,0,0.14), 0 1px 0 rgba(255,255,255,0.6) inset' }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 37, background: page, overflow: 'hidden', position: 'relative', display: 'flex', flexDirection: 'column' }}>
          <StatusBar t={t} />
          {/* nav */}
          <div style={{ height: 44, display: 'flex', alignItems: 'center', padding: '0 12px', position: 'relative' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 2, color: sysBlue, fontSize: 16 }}>
              <svg width="11" height="18" viewBox="0 0 11 18" fill="none" stroke={sysBlue} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M9 2L3 9l6 7" /></svg>
              <span style={{ fontWeight: 400 }}>レポート</span>
            </span>
            <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 16, fontWeight: 600, color: t.label, fontFamily: d.displayFont }}>設定</span>
          </div>

          <div style={{ flex: 1, padding: '8px 0', overflow: 'hidden' }}>
            {/* 表示 */}
            <SecHead>表示</SecHead>
            <div style={{ margin: '0 16px', background: cell, borderRadius: 11 }}>
              <div style={{ display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12 }}>
                <span style={{ fontSize: 15, color: t.label, flex: 1 }}>ボタンを表示</span>
                <Switch on={showButton} color={sysGreen} />
              </div>
            </div>
            <Foot>オフにすると、シェイク操作のみでレポートを起動します。</Foot>

            {/* 録画 */}
            <div style={{ height: 22 }} />
            <SecHead>保持する録画の長さ</SecHead>
            <div style={{ margin: '0 16px', background: cell, borderRadius: 11, overflow: 'hidden' }}>
              {opts.map((s, i) =>
              <div key={s} style={{ display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12, borderTop: i ? `0.5px solid ${sep}` : 'none' }}>
                  <span style={{ fontSize: 15, color: t.label, flex: 1, fontVariantNumeric: 'tabular-nums' }}>{s} 秒</span>
                  {s === seconds && <span style={{ color: sysBlue, display: 'flex' }}><Icon name="check" size={17} color={sysBlue} sw={2.2} /></span>}
                </div>
              )}
            </div>
            <Foot>選択した秒数の録画を常に保持し、発火時に書き出します。長いほどメモリを使います。</Foot>

            {/* 録画（権限） */}
            <div style={{ height: 22 }} />
            <SecHead>録画</SecHead>
            <div style={{ margin: '0 16px', background: cell, borderRadius: 11, overflow: 'hidden' }}>
              <div style={{ display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12 }}>
                <span style={{ fontSize: 15, color: t.label, flex: 1 }}>画面収録の権限</span>
                <span style={{ fontSize: 14, color: granted ? t.success : t.danger, fontWeight: 500 }}>{granted ? '許可済み' : '未許可'}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', padding: '12px 14px', gap: 12, borderTop: `0.5px solid ${sep}` }}>
                <span style={{ fontSize: 15, color: sysBlue, flex: 1 }}>iOS の設定を開く</span>
                <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke={t.secondary} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M5 11L11 5M11 5H6M11 5v5" /></svg>
              </div>
            </div>
            <Foot>画面収録が許可されていないとクリップを保持できません。iOS の設定 → プライバシー で許可してください。</Foot>
          </div>

          <div style={{ height: 22, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 7 }}>
            <div style={{ width: 110, height: 4.5, borderRadius: 3, background: t.label, opacity: 0.85 }} />
          </div>
        </div>
      </div>
    </div>);

}

// ── Trigger (floating bug) + status toast, per direction ────────────────
function TriggerToast({ d, scheme = 'light' }) {
  const t = d[scheme];
  const act = t.ctrl || t.accent;
  const onAct = t.onCtrl || t.onAccent;
  const tuck = '#9AA0A8'; // parked/dormant neutral
  const states = [
  { label: '通常', ring: false, scale: 1 },
  { label: '長押し中', ring: true, scale: 0.92 },
  { label: '端タック中', ring: false, scale: 1, tucked: true },
  { label: '休止（録画OFF）', ring: false, scale: 1, dormant: true }];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', gap: 18, alignItems: 'flex-end' }}>
        {states.map((s) =>
        <div key={s.label} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
            <div style={{ position: 'relative', width: 56, height: 56, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {s.ring && <div style={{ position: 'absolute', inset: -4, borderRadius: '50%', border: `3px solid ${act}`, opacity: 0.35 }} />}
              {s.ring && <div style={{ position: 'absolute', inset: -4, borderRadius: '50%', background: `conic-gradient(${act} 70%, transparent 0)`, WebkitMask: 'radial-gradient(circle, transparent 22px, #000 23px)', mask: 'radial-gradient(circle, transparent 22px, #000 23px)' }} />}
              <div style={{
              width: 50, height: 50, borderRadius: s.tucked ? '25px 0 0 25px' : '50%',
              background: s.dormant ? tuck : act, display: 'flex', alignItems: 'center', justifyContent: 'center',
              transform: `scale(${s.scale}) ${s.tucked ? 'translateX(11px)' : ''}`,
              boxShadow: '0 4px 12px rgba(0,0,0,0.22)', opacity: s.dormant ? 1 : s.tucked ? 0.82 : 1,
              transition: 'all .2s'
            }}>
                <CleanMark ring={onAct} wedge={onAct} wedgeOpacity={s.dormant ? 0.6 : 0.5} hub={onAct} size={32} sw={3} />
              </div>
            </div>
            <span style={{ fontSize: 11, color: t.secondary }}>{s.label}</span>
          </div>
        )}
      </div>
      {/* toasts */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {[['記憶を辿っています…', false], ['記憶の書き出しに失敗しました', 'err']].map(([msg, ok]) =>
        <div key={msg} style={{
          alignSelf: 'flex-start', display: 'inline-flex', alignItems: 'center', gap: 8,
          padding: '7px 13px', borderRadius: 20,
          background: scheme === 'light' ? 'rgba(20,20,24,0.88)' : 'rgba(245,245,250,0.95)',
          color: scheme === 'light' ? '#fff' : '#15151a',
          fontSize: 12, fontWeight: 500, boxShadow: '0 4px 14px rgba(0,0,0,0.18)'
        }}>
            {ok === 'err' ? <span style={{ width: 13, height: 13, borderRadius: 7, background: t.danger, color: '#fff', fontSize: 9, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>!</span> :
          <span style={{ width: 11, height: 11, borderRadius: 6, border: `2px solid ${scheme === 'light' ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.3)'}`, borderTopColor: act, display: 'inline-block' }} />}
            {msg}
          </div>
        )}
      </div>
    </div>);

}

Object.assign(window, { Icon, LogoMark, Wordmark, SwatchStrip, PhoneReportView, PhoneSettingsView, TriggerToast, StatusBar });