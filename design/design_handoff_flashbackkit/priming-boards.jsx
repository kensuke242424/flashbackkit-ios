/* priming-boards.jsx — FlashbackKit：許可プライミングの解説/比較/フロー/コピー/仕様ボード
   Exports to window: PrimeIntroBoard, FormatCompareBoard, PrimeFlowBoard,
                      CopyBoard, PrimeSpecBoard.
   uses globals: PrimingPhone, COPY, SystemAlert, CleanMark, Icon, StatusBar, window.DIRECTIONS */

(function () {
  const Q = window.DIRECTIONS[2];
  const L = Q.light;
  const UI = { ink: '#1c1d24', sub: '#6A6B74', rule: '#ECECEF', faint: '#F7F7F9', soft: '#FBFBFC' };
  const mono = { fontFamily: 'var(--mono)' };
  const orange = L.ctrl;

  const H = ({ children }) => <div style={{ fontSize: 19, fontWeight: 700, color: UI.ink, letterSpacing: '-0.01em' }}>{children}</div>;
  const Sub = ({ children, max = 920 }) => <div style={{ fontSize: 12.5, color: '#46474f', lineHeight: 1.55, margin: '5px 0 18px', maxWidth: max, textWrap: 'pretty' }}>{children}</div>;
  const Cap = ({ children }) => <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: UI.sub, marginBottom: 12 }}>{children}</div>;
  const B = ({ children }) => <b style={{ color: UI.ink, fontWeight: 600 }}>{children}</b>;
  const O = ({ children }) => <b style={{ color: orange, fontWeight: 600 }}>{children}</b>;
  const Mono = ({ children }) => <span style={{ ...mono, fontSize: 11.5, background: UI.faint, padding: '1px 5px', borderRadius: 4, color: '#2f3038' }}>{children}</span>;

  function Board({ children, pad = 30 }) {
    return <div style={{ width: '100%', height: '100%', background: '#fff', padding: pad, boxSizing: 'border-box', fontFamily: 'var(--sf)', color: UI.ink, overflow: 'hidden' }}>{children}</div>;
  }

  function Pill({ children, c = UI.sub, bg = UI.faint }) {
    return <span style={{ display: 'inline-flex', alignItems: 'center', padding: '4px 10px', borderRadius: 13, background: bg, border: `1px solid ${UI.rule}`, fontSize: 11.5, fontWeight: 600, color: c }}>{children}</span>;
  }

  // ── 1. 概要 & 推奨 ──────────────────────────────────────────────────────
  function PrimeIntroBoard() {
    const Decision = ({ q, a, why }) => (
      <div style={{ display: 'flex', gap: 14, padding: '13px 0', borderTop: `1px solid ${UI.rule}` }}>
        <div style={{ flex: '0 0 240px' }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: UI.ink, lineHeight: 1.45 }}>{q}</div>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12.5, color: orange, fontWeight: 700, marginBottom: 3 }}>{a}</div>
          <div style={{ fontSize: 12, color: UI.sub, lineHeight: 1.55 }}>{why}</div>
        </div>
      </div>
    );
    return (
      <Board pad={34}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.1em', color: orange, marginBottom: 9 }}>PERMISSION PRIMING · 画面収録の許可</div>
        <div style={{ fontSize: 27, fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1.12 }}>OS の「画面収録」確認の<br />前に出す、橋渡しの画面</div>
        <Sub max={880}>
          画面収録の許可は ReplayKit が出す<B>iOS システムアラート</B>で、本文もボタン文言も<B>アプリ側でカスタムできない</B>（カメラ等の usage string も無い）。差し込めるのは<B>アプリ表示名だけ</B>。
          そこで「次に出る確認で『許可』を押すと、直前の操作の録画を自動で保持できる」ことを<B>押す前に</B>中立に伝え、理解と許可率を上げる画面を用意する。
          確定方向「Quiet」に従い、システム純正に溶かす・脅かさない・<B>不具合/バグの語は使わない</B>。
        </Sub>

        <Cap>5 つの論点への提案</Cap>
        <div style={{ borderBottom: `1px solid ${UI.rule}` }}>
          <Decision q="① 提示形式は？" a="半モーダル（.sheet / .medium）を主案" why="プライミングは軽量（マーク＋文＋ボタン）。ReportView 本体がフルスクリーン確定なので、その上に薄いシートを重ねると『あと一歩』が自然に伝わる。ReportView でハーフを退けた理由（動画＋トリムの操作量）は本画面に当てはまらない。フル/状態案も併記して比較可。" />
          <Decision q="② レイアウト要素は？" a="Time Slice マーク＋見出し＋橋渡し文＋主CTA＋『あとで』" why="3ステップ図解は『あり版』も用意したが、Quiet の思想では最小が望ましい。代わりに『タップすると iOS の確認が表示されます』の一文で“次の挙動”を予告（＝許可率の肝）。" />
          <Decision q="③ ボタン構成は？" a="1ボタン（許可へ進む）＋テキスト『あとで』" why="脅かさない・誘導しすぎないトーンに最適。等価2ボタン版も比較用に提示。" />
          <Decision q="④ 主CTAの色は？" a="オレンジ（＝これから録画を有効にする操作）" why="色ルール『オレンジ＝録画/操作可能』に整合。CTA は録画を ON にする導線そのものなのでオレンジが妥当。一方ヒーローの Time Slice マークは“まだ録画していない”ため中立スレートに留め、ルールを濁さない。" />
          <Decision q="⑤ いつ出す？（決定方針）" a="既定は起動時オフ。録画ON操作時に端末で1回だけ" why="この機能は使わない人もいる。起動のたびに許可確認が出るのは煩わしい。そこで既定では起動時に権限確認を発火せず、ユーザーは必ず録画オフの ReportView を通る。明示的に『録画をオンにする』を押した時、本プライミングを端末で1回だけ提示。以降は録画ON操作で直接 OS 確認へ。設定に『アプリ起動時に権限を確認する』トグル（既定オフ／オンで起動直後に即 OS 確認）を用意。" />
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 18, flexWrap: 'wrap' }}>
          <Pill c={orange} bg="rgba(217,130,28,0.08)">許可済み・非対応端末では出さない</Pill>
          <Pill>「あとで」→ dormant（録画オフ）へ戻る</Pill>
          <Pill>iOS 16+ / SwiftUI / L&D / Dynamic Type / VoiceOver</Pill>
          <Pill>新規依存ゼロ・通信なし</Pill>
        </div>
      </Board>
    );
  }

  // ── 2. 提示形式の比較 ───────────────────────────────────────────────────
  function FormatCompareBoard() {
    const Col = ({ title, badge, phone, pros, cons, recommend }) => (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 4 }}>
          <span style={{ fontSize: 13.5, fontWeight: 700, color: UI.ink }}>{title}</span>
          {recommend && <span style={{ fontSize: 10, fontWeight: 700, color: '#fff', background: orange, padding: '2px 7px', borderRadius: 9 }}>推奨</span>}
        </div>
        <div style={{ fontSize: 11, color: UI.sub, ...mono, marginBottom: 14 }}>{badge}</div>
        {phone}
        <div style={{ marginTop: 16, width: '100%', maxWidth: 300 }}>
          <div style={{ display: 'flex', gap: 5, alignItems: 'flex-start', marginBottom: 6 }}>
            <span style={{ color: '#1F8A5B', fontWeight: 700, fontSize: 12 }}>＋</span>
            <span style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.5 }}>{pros}</span>
          </div>
          <div style={{ display: 'flex', gap: 5, alignItems: 'flex-start' }}>
            <span style={{ color: '#C0392B', fontWeight: 700, fontSize: 12 }}>−</span>
            <span style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.5 }}>{cons}</span>
          </div>
        </div>
      </div>
    );
    return (
      <Board>
        <H>提示形式の比較 — ①半モーダル / ②フルスクリーン / ③ReportView 内の一状態</H>
        <Sub>同じコピー（中立・説明型 A）で 3 形式を並列。<B>主案は ①半モーダル</B>。dormant の上に薄く重なり離脱も容易で、プライミングの軽さに最も合う。フルは存在感が要るとき、状態案は dormant / justEnabled と完全に同列に並べたいときの選択肢。</Sub>
        <div style={{ display: 'flex', gap: 20, marginTop: 4 }}>
          <Col title="① 半モーダル" badge=".sheet([.medium])" recommend
            phone={<PrimingPhone d={Q} scheme="light" format="sheet" variant="A" />}
            pros="軽量で割り込み感が少ない。背後の dormant が透け、文脈を失わない。下スワイプ/あとで で即離脱。"
            cons="縦の情報量は限られる。グラバーと『あとで』の役割が近い。" />
          <Col title="② フルスクリーン" badge=".fullScreenCover"
            phone={<PrimingPhone d={Q} scheme="light" format="full" variant="A" />}
            pros="存在感が強く、初回オンボーディングなど“きちんと読ませたい”場面に向く。"
            cons="プライミングには重い。Quiet の非干渉と相性が弱く、離脱の心理的コストが上がる。" />
          <Col title="③ ReportView 内の状態" badge="emptyReason: .priming"
            phone={<PrimingPhone d={Q} scheme="light" format="state" variant="A" />}
            pros="dormant / justEnabled と完全に同列の“状態”として馴染む。実装も既存 enum 拡張で最小。"
            cons="dormant とほぼ同居で差が薄い。許可導線としての“1 アクション感”が出にくい。" />
        </div>
      </Board>
    );
  }

  // ── 3. フロー上の位置 ───────────────────────────────────────────────────
  function PrimeFlowBoard() {
    const MiniPhone = ({ children, scheme = 'light' }) => (
      <div style={{ width: 150, height: 320, borderRadius: 26, background: scheme === 'dark' ? '#000' : '#dcdce0', padding: 3, boxShadow: '0 6px 18px rgba(0,0,0,0.12)', flex: '0 0 auto' }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 23, overflow: 'hidden', position: 'relative', background: scheme === 'dark' ? '#000' : '#fff' }}>{children}</div>
      </div>
    );
    const Arrow = ({ label }) => (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flex: '0 0 auto', alignSelf: 'center' }}>
        <span style={{ fontSize: 10, color: orange, fontWeight: 700, whiteSpace: 'nowrap' }}>{label}</span>
        <svg width="34" height="14" viewBox="0 0 34 14" fill="none" stroke={orange} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M2 7h28M24 2l6 5-6 5" /></svg>
      </div>
    );
    const Tile = ({ title, sub }) => (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
        <div style={{ fontSize: 11.5, fontWeight: 700, color: UI.ink }}>{title}</div>
        <div style={{ fontSize: 10, color: UI.sub, textAlign: 'center', lineHeight: 1.4, maxWidth: 150 }}>{sub}</div>
      </div>
    );
    // tiny dormant + justEnabled glyph mocks
    const NavMini = ({ t, share }) => (
      <div style={{ height: 26, display: 'flex', alignItems: 'center', padding: '0 10px', position: 'relative' }}>
        <span style={{ color: t.ctrl }}><Icon name="close" size={13} sw={2} /></span>
        <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 10, fontWeight: 600, color: t.label }}>Flashback</span>
        <span style={{ marginLeft: 'auto', color: t.ctrl }}><Icon name="gear" size={12} sw={1.7} /></span>
      </div>
    );
    const BoxMini = ({ t, ring, wedge, wo, hub, head, headColor }) => (
      <div style={{ margin: '6px 10px', height: 96, borderRadius: 10, background: t.fieldBg, border: `1px dashed ${t.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
        <CleanMark ring={ring} wedge={wedge} wedgeOpacity={wo} hub={hub} size={26} sw={3.4} />
        <span style={{ fontSize: 9.5, fontWeight: 600, color: headColor }}>{head}</span>
      </div>
    );
    return (
      <Board>
        <H>フロー上の位置 — 再試行パス（本命）</H>
        <Sub><B>dormant（録画オフ）</B>で『録画をオンにする』をタップ → <O>本プライミング画面</O> → 『許可へ進む』→ <B>OS の画面収録確認（カスタム不可）</B> → 許可 → 既存の <B>justEnabled（録画オン直後）</B> へ。<B>「あとで」</B>はいつでも dormant に戻すだけで、エラーにしない。</Sub>

        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6, marginTop: 6 }}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <MiniPhone><NavMini t={L} /><BoxMini t={L} ring={L.tertiary} wedge={L.secondary} wo={0.55} hub={L.tertiary} head="録画はオフです" headColor={L.secondary} />
              <div style={{ margin: '2px 10px', display: 'flex', alignItems: 'center', gap: 5, color: L.ctrl }}><CleanMark ring={L.ctrl} wedge={L.ctrl} wedgeOpacity={0.5} hub={L.ctrl} size={11} sw={3.4} /><span style={{ fontSize: 10, fontWeight: 600 }}>録画をオンにする</span></div>
            </MiniPhone>
            <Tile title="dormant" sub="休止FAB→即 ReportView・録画オフ" />
          </div>

          <Arrow label="オンにする" />

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <MiniPhone>
              {/* dimmed dormant behind */}
              <div style={{ position: 'absolute', inset: 0, opacity: 0.55 }}>
                <NavMini t={L} />
                <BoxMini t={L} ring={L.tertiary} wedge={L.secondary} wo={0.55} hub={L.tertiary} head="録画はオフです" headColor={L.secondary} />
              </div>
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.32)' }} />
              {/* sheet */}
              <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 196, background: '#fff', borderRadius: '14px 14px 0 0', display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '8px 14px 0', boxShadow: '0 -6px 18px rgba(0,0,0,0.25)' }}>
                <div style={{ width: 26, height: 4, borderRadius: 2, background: L.tertiary, opacity: 0.6 }} />
                <div style={{ marginTop: 12 }}><CleanMark ring={L.accent} wedge={L.accent} wedgeOpacity={0.45} hub={L.accent} size={26} sw={3.4} /></div>
                <div style={{ fontSize: 10, fontWeight: 700, color: L.label, marginTop: 8, textAlign: 'center' }}>画面収録をオンにします</div>
                <div style={{ width: '100%', height: 28, borderRadius: 8, background: L.ctrl, color: L.onCtrl, fontSize: 10, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 12 }}>許可へ進む</div>
                <div style={{ fontSize: 9.5, color: L.secondary, marginTop: 8 }}>あとで</div>
              </div>
            </MiniPhone>
            <Tile title="プライミング" sub="本画面（半モーダル）・端末で1回だけ" />
          </div>

          <Arrow label="許可へ進む" />

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <MiniPhone>
              <div style={{ position: 'absolute', inset: 0, background: '#15151b' }} />
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)' }} />
              <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div style={{ transform: 'scale(0.62)' }}><SystemAlert scheme="dark" appName="DemoApp" /></div>
              </div>
            </MiniPhone>
            <Tile title="OS 確認" sub="ReplayKit のシステム表示・文言/ボタンはカスタム不可" />
          </div>

          <Arrow label="許可" />

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <MiniPhone><NavMini t={L} />
              <BoxMini t={L} ring={L.ctrl} wedge={L.ctrl} wo={1} hub={L.ctrl} head="録画をオンにしました" headColor={L.label} />
              <div style={{ display: 'flex', justifyContent: 'center', marginTop: 2 }}><span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 7px', borderRadius: 9, background: 'rgba(217,130,28,0.12)' }}><span style={{ width: 5, height: 5, borderRadius: 3, background: L.ctrl }} /><span style={{ fontSize: 9, fontWeight: 600, color: L.ctrl }}>録画中</span></span></div>
            </MiniPhone>
            <Tile title="justEnabled" sub="既存『録画オン直後』状態へ合流" />
          </div>
        </div>

        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 22, paddingTop: 16, display: 'flex', gap: 16 }}>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '13px 16px' }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink, marginBottom: 5 }}>起動時の方針（決定）</div>
            <div style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.6 }}>この機能は使わない人もいる。起動のたびに許可確認が出るのは煩わしいため、<B>既定では起動時に権限確認を発火しない</B>（<Mono>primeOnLaunch = false</Mono>）。ユーザーは必ず録画オフの ReportView を通り、<B>明示的に『録画をオンにする』を押した時だけ</B>本プライミングが出る。</div>
          </div>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '13px 16px' }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink, marginBottom: 5 }}>端末で1回だけ・以降の挙動</div>
            <div style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.6 }}>プライミングは<B>端末につき一度だけ</B>（<Mono>hasPrimed</Mono> フラグ）。<B>2回目以降は録画ON操作で直接 OS 確認</B>へ。<B>許可済み</B>・<B>非対応端末（Simulator）</B>では出さない。<B>「あとで」</B>→ dormant に戻すだけ（トーストもエラーも出さない）。設定の<B>「アプリ起動時に権限を確認する」トグル</B>（既定オフ）で、起動直後の即時確認も選べる。</div>
          </div>
        </div>
      </Board>
    );
  }

  // ── 4. コピー案（複数バリエーション） ───────────────────────────────────
  function CopyBoard() {
    const Row = ({ k, c }) => (
      <div style={{ display: 'flex', gap: 18, padding: '16px 0', borderTop: `1px solid ${UI.rule}`, alignItems: 'flex-start' }}>
        <div style={{ flex: '0 0 170px' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: k === 'A' ? orange : UI.ink }}>{c.tag}</div>
        </div>
        <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px 24px' }}>
          <Field label="見出し" v={c.head} big />
          <Field label="主CTA / 副導線" v={`${c.cta}  ·  ${c.later}`} />
          <Field label="本文（OS確認への橋渡し）" v={c.body} span />
          <Field label="ヒント（予告）" v={c.hint} span />
        </div>
      </div>
    );
    const Field = ({ label, v, big, span }) => (
      <div style={{ gridColumn: span ? '1 / -1' : 'auto' }}>
        <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.04em', color: UI.sub, marginBottom: 3 }}>{label}</div>
        <div style={{ fontSize: big ? 15 : 12.5, fontWeight: big ? 700 : 400, color: UI.ink, lineHeight: 1.5 }}>{v}</div>
      </div>
    );
    return (
      <Board>
        <H>コピー案 — 3 バリエーション（見出し / 本文 / ボタン）</H>
        <Sub>すべて日本語・ブランド名/タグラインは英語のまま・<B>「不具合/バグ」表現は不使用</B>。SDK は「直前の録画を呼び戻せる」ことだけを述べ、用途は問わない中立コピー方針。<O>A（中立・説明型）を既定として推奨</O>。</Sub>
        <div style={{ borderBottom: `1px solid ${UI.rule}` }}>
          {['A', 'B', 'C'].map((k) => <Row key={k} k={k} c={COPY[k]} />)}
        </div>
        <div style={{ display: 'flex', gap: 14, marginTop: 16 }}>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '12px 15px' }}>
            <div style={{ fontSize: 11.5, fontWeight: 700, color: UI.ink, marginBottom: 4 }}>文言の注意</div>
            <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>OS 確認の<B>ボタン文言（「収録を開始」等）は iOS バージョンで変わる</B>ため、本文では引用せず「許可を選ぶ」と一般化する。マイク収録を併用しない限り音声には触れない。</div>
          </div>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '12px 15px' }}>
            <div style={{ fontSize: 11.5, fontWeight: 700, color: UI.ink, marginBottom: 4 }}>VoiceOver</div>
            <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>主CTA ラベル「許可へ進む、iOS の確認を表示します」。マークは <Mono>isHidden</Mono> 装飾扱い。見出し→本文→CTA の読み上げ順を保証。</div>
          </div>
        </div>
      </Board>
    );
  }

  // ── 5. 使用トークン & SF Symbols & README 追記 ─────────────────────────
  function PrimeSpecBoard() {
    const Tok = ({ name, role, light, dark }) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 0', borderTop: `1px solid ${UI.rule}` }}>
        <div style={{ display: 'flex', gap: 4, flex: '0 0 auto' }}>
          <span style={{ width: 18, height: 18, borderRadius: 5, background: light, boxShadow: 'inset 0 0 0 1px rgba(0,0,0,0.12)' }} />
          <span style={{ width: 18, height: 18, borderRadius: 5, background: dark, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.12)' }} />
        </div>
        <span style={{ fontSize: 12, fontWeight: 600, color: UI.ink, flex: '0 0 150px' }}>{name}</span>
        <span style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.4 }}>{role}</span>
      </div>
    );
    const Sym = ({ name, use }) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0' }}>
        <span style={{ ...mono, fontSize: 11.5, color: orange, flex: '0 0 130px' }}>{name}</span>
        <span style={{ fontSize: 11.5, color: UI.sub }}>{use}</span>
      </div>
    );
    return (
      <Board>
        <div style={{ display: 'flex', gap: 30 }}>
          <div style={{ flex: '1 1 0', minWidth: 0 }}>
            <H>使用トークン & SF Symbols</H>
            <Sub max={520}>ブランド2色（Action-Orange / Slate）以外は semantic system color。本画面は新規トークンを足さない。</Sub>
            <Cap>トークン（左：Light / 右：Dark）</Cap>
            <div style={{ borderBottom: `1px solid ${UI.rule}`, marginBottom: 18 }}>
              <Tok name="Action / Orange" role="主CTA の地。色ルール『録画/操作可能』。L #D9821C · D #E8A23E" light={Q.light.ctrl} dark={Q.dark.ctrl} />
              <Tok name="Brand neutral / Slate" role="ヒーローの Time Slice マーク（“まだ録画していない”中立）。L #5B6472 · D #8B94A3" light={Q.light.accent} dark={Q.dark.accent} />
              <Tok name="label / secondary" role="見出し＝label、本文＝secondaryLabel" light={Q.light.label} dark={Q.dark.label} />
              <Tok name="tertiaryLabel" role="ヒント文・グラバー" light={Q.light.tertiary} dark={Q.dark.tertiary} />
              <Tok name="sheet surface" role="シートの地。L systemBackground #FFF / D secondarySystemBackground #1C1C1E" light="#FFFFFF" dark="#1C1C1E" />
              <Tok name="separator" role="2ボタン版アウトライン・破線箱" light={Q.light.separator} dark={Q.dark.separator} />
            </div>
            <Cap>SF Symbols</Cap>
            <Sym name="xmark" use="キャンセル（フル/状態案の左上）" />
            <Sym name="gearshape" use="設定（状態案のナビ右）" />
            <Sym name="info.circle" use="ヒント文の先頭（任意）" />
            <Sym name="iphone / app" use="環境情報（状態案）" />
            <div style={{ fontSize: 11, color: UI.sub, marginTop: 8, lineHeight: 1.5 }}>幾何形状（リング＋扇＋ハブ）の Time Slice マークは <Mono>Shape</Mono> で再現。CTA は SF Symbol ではなくテキストボタン。</div>
          </div>

          <div style={{ flex: '1 1 0', minWidth: 0, borderLeft: `1px solid ${UI.rule}`, paddingLeft: 30 }}>
            <H>README 追記文</H>
            <Sub max={520}>既存ハンドオフ「Screens / Views」に新節として追加する想定の本文。</Sub>
            <div style={{ background: '#0f1115', borderRadius: 10, padding: '16px 18px', fontFamily: 'var(--mono)', fontSize: 10.8, lineHeight: 1.65, color: '#c9ccd6', overflow: 'hidden' }}>
              <div style={{ color: '#e8a23e' }}>### 5. Screen-Recording Priming (pre-permission)</div>
              <br />
              <span style={{ color: '#7f8794' }}>**Purpose:**</span> bridge to the un-customizable iOS<br />
              screen-recording system alert (ReplayKit). The OS<br />
              alert body/buttons can't be themed — only the app<br />
              display name. Prime *before* it to lift grant rate.<br /><br />
              <span style={{ color: '#7f8794' }}>**Presentation:**</span> half-sheet <span style={{ color: '#e8a23e' }}>`.presentationDetents([.medium])`</span><br />
              over the dormant ReportView. (full-screen & an<br />
              in-ReportView <span style={{ color: '#e8a23e' }}>`.priming`</span> state are kept as alts.)<br /><br />
              <span style={{ color: '#7f8794' }}>**Flow:**</span> dormant → tap「録画をオンにする」→<br />
              <b style={{ color: '#c9ccd6' }}>priming</b> →「許可へ進む」→ OS alert → granted →<br />
              <span style={{ color: '#e8a23e' }}>`justEnabled`</span>. 「あとで」returns to dormant (no toast).<br /><br />
              <span style={{ color: '#7f8794' }}>**Color:**</span> CTA = Action-Orange (enabling recording).<br />
              Hero Time Slice mark = Slate-neutral (not yet<br />
              recording) — keeps「orange = recording」intact.<br /><br />
              <span style={{ color: '#7f8794' }}>**Copy (default A):**</span> 見出し「画面収録をオンにします」/<br />
              本文「次に表示される iOS の確認で『許可』を選ぶと、<br />
              アプリ内の直前の操作を自動で保持できます。」/ CTA<br />
              「許可へ進む」「あとで」. Keep it short; clarify<br />
              アプリ内 (in-app) scope. Avoid 不具合/バグ wording.<br /><br />
              <span style={{ color: '#7f8794' }}>**Don't show** when granted or recording unsupported<br />
              (Simulator). Show ONCE per device (`hasPrimed`);<br />
              after that, 録画ON → OS alert directly. Launch:<br />
              default OFF (no launch prompt). Settings toggle<br />
              「アプリ起動時に権限を確認する」(default off) → on<br />
              fires startCapture right after launch.</span>
            </div>
          </div>
        </div>
      </Board>
    );
  }

  Object.assign(window, { PrimeIntroBoard, FormatCompareBoard, PrimeFlowBoard, CopyBoard, PrimeSpecBoard });
})();
