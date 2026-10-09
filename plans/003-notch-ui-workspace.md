# 003 — Notch workspace UI: Shelf, Clipboard, Usage และ rice mascot

- **Status**: PLAN — ยังไม่เขียนโค้ด รอเจ้าของอนุมัติ 3 ข้อในหัวข้อ "ต้องตัดสินใจก่อนเริ่ม"
- **Owner**: Code Coach — Notch UI session (Claude Code, Opus 5.5)
- **Source brief**: `../CLAUDE_NOTCH_FEATURE_HANDOFF.md`, `../CLAUDE.md`
- **Target**: `CoucouHub` target เท่านั้น (`COUCOU_HUB`, bundle `com.hubisland.desktop`)
- **Base**: branch `integration/linkhub-tincan` @ `1659072` + งาน backend ที่ยังไม่ commit ของ Codex

## 1. Context

เจ้าของต้องการเครื่องมือ 4 อย่างใน notch: file shelf, clipboard, การ์ด AI usage
และ mascot ข้าวสีขาว/ทองที่มีชีวิตชีวากว่าเดิม ฝั่ง backend (Codex) ทำเสร็จแล้วและผ่าน
acceptance:

| Backend | สิ่งที่ UI ได้ใช้ |
| --- | --- |
| `CoucouWorkspaceStore` | `files`, `lastError`, `addFiles`, `removeFile`, `clear` — เก็บแค่ reference ใน memory, ไม่แตะไฟล์ต้นฉบับ, สูงสุด 50 ไฟล์ |
| `CoucouClipboardAccessService` | ปิดไว้เป็นค่าเริ่มต้น, ไม่มี timer ภายใน; `enableChangeMonitoring`, `captureManually`, `captureIfChanged`, `history`, `removeSnapshot`, `clearHistory`; `snapshot.makeItemProviders()` สำหรับลาก, `snapshot.recopy(to:)` สำหรับปุ่ม Copy |
| `CoucouUsageSnapshot.claude(_:)` | `available / stale / unavailable`, `windows` (five-hour, seven-day), `observedAt`, `source` |
| `CoucouHubIntegration.shared` | `workspace`, `clipboard`, `stageFiles`, `fileShelfError`, `claudeUsage` |
| `FileDropHandler` (COUCOU_HUB) | drop → `stageFiles(urls)` แล้ว return แล้ว (ไม่มี upload animation ปลอม) |

ตอนนี้ยังไม่มี UI ไหนแสดงสิ่งเหล่านี้ งานของแผนนี้คือ **presentation + mascot เท่านั้น**

## 2. ต้องตัดสินใจก่อนเริ่ม (3 ข้อ)

### D1 — จะเข้าถึง 4 ส่วนนี้จากตรงไหน (แนะนำ: rail แนวตั้งใต้ Mochi)

ข้อห้าม: ห้ามเพิ่มป้ายเล็กๆ ลงใน header ของ Agents ที่แน่นอยู่แล้ว (Agents · Trail · MCP · Review
+ สถานะ + 3 ปุ่ม)

ข้อเท็จจริงเรื่องพื้นที่: pane สูง 310pt, gutter ซ้ายกว้าง 84pt ตอนนี้ Mochi ขนาด 46pt
อยู่**กลางแนวตั้ง** (`botX 54`, คำนวณ cy ≈ 176) จึงเหลือพื้นที่บน/ล่างไม่พอใส่ปุ่ม 4 ปุ่ม

**แนะนำ:** ย้าย Mochi ไปชิดบนของ gutter (`botY` คงที่ ≈ 74 ใน `IslandConst.viewLayouts[.linkHub]`)
แล้ววาง rail 4 ปุ่มใต้ Mochi: Agents / Shelf / Clipboard / Usage

- ปุ่มเป็นไอคอน capsule 30×24 แบบเดียวกับ `TabButton` (`#1D1F23` ตอนเลือก, hover `white 0.07`)
- ไม่มี text label, มี `.help()` และ `accessibilityLabel` ทุกปุ่ม
- Badge เล็กๆ: Shelf = จำนวนไฟล์, Clipboard = จุดเขียวเมื่อเปิด history
- ตำแหน่ง Mochi และ rail **คงที่ทุก section** จึงตอบโจทย์ "anchor ไม่ขยับ"
- pane นี้เป็นของ fork อย่างเดียว (ไม่อยู่ใน `main`) จึงไม่ผิดกฎ "ห้าม restyle สิ่งที่ ship แล้ว"

ทางเลือกอื่นที่ไม่แนะนำ: ใส่เมนู dropdown ใน header (ค้นหายาก) หรือเพิ่มปุ่มใน `IslandHeader`
ตัวบนสุด (ปนกับ chat/upload ของ Coucou เดิม)

### D2 — rice mascot จะไปแทน Mochi แค่ไหน (แนะนำ: เฉพาะใน workspace pane)

- **แนะนำ:** ใน build `CoucouHub` เมื่อ `state.view == .linkHub` ซ่อน `BotCanvasView` ตัวหลัก
  แล้ววาด `RiceMascotView` ตัวใหม่ที่ gutter แทน ส่วน view อื่น (chat, settings, compact, hidden)
  ยังเป็น Mochi เดิมทั้งหมด
- ทางเลือก: แทน Mochi ทุกที่ใน CoucouHub — ต้องรองรับทุก state ของ `BotState`,
  ท่าเต้นตอนเล่นเพลง และ outfit ซึ่งใหญ่กว่ามาก แนะนำให้ทำเป็นเฟสถัดไป
- ทั้งสองแบบ: build ของ App Store / NotchBuddy ไม่เปลี่ยนเลย

### D3 — clipboard history ตรวจตอนไหน (แนะนำ: เฉพาะตอน island เปิดอยู่)

กฎในโปรเจกต์: CPU ต้องเป็น 0% เมื่อ island ซ่อน และ backend ตั้งใจไม่มี timer ภายใน

- **แนะนำ:** เมื่อผู้ใช้เปิด history แล้ว UI จะเรียก `captureIfChanged()` 1 ครั้งทุกครั้งที่ island
  เปิดขึ้นมา และทุก 1 วินาที**ระหว่างที่ island เปิดอยู่เท่านั้น** หยุดทันทีที่ island ซ่อน
- ข้อจำกัดที่ต้องบอกในหน้า UI ตรงๆ: ถ้า copy หลายครั้งระหว่างที่ island ซ่อน จะเก็บได้แค่อันล่าสุด
- ทางเลือก: ตรวจทุก 1 วินาทีตลอดเวลาที่เปิด history (เก็บได้ครบกว่า แต่ CPU จะไม่เป็น 0% ตอนซ่อน
  ซึ่งผิดกฎ ต้องให้เจ้าของยกเว้นกฎนั้นเอง)
- สถานะเปิด/ปิด history ไม่บันทึกข้ามการเปิดแอป (ตาม backend: session-only, เริ่มต้นปิดทุกครั้ง)

## 3. โครงสร้างไฟล์

ไฟล์ใหม่ทั้งหมดอยู่ใน `NotchBuddy/Sources/App/` ครอบด้วย `#if COUCOU_HUB`
(target NotchBuddy ก็ glob `Sources/App` ด้วย จึงต้องครอบเพื่อไม่ให้ App Store build เปลี่ยน)
XcodeGen glob `Sources` อยู่แล้ว เพิ่มไฟล์แล้วรัน `xcodegen` ก็พอ ไม่ต้องแก้ `project.yml`

| ไฟล์ | ใหม่/แก้ | หน้าที่ |
| --- | --- | --- |
| `CoucouWorkspaceSection.swift` | ใหม่ | `enum CoucouWorkspaceSection { agents, shelf, clipboard, usage }`, `CoucouWorkspaceRail` view, `Notification.Name.coucouWorkspaceShowSection` |
| `CoucouWorkspacePresentation.swift` | ใหม่ | helper แบบ Foundation ล้วน (ทดสอบได้ด้วย `swiftc`): ข้อความการ์ด usage, เวลา relative, ขนาดไฟล์, ตัดข้อความ preview clipboard, ข้อความ error |
| `CoucouShelfPane.swift` | ใหม่ | หน้า file shelf |
| `CoucouClipboardPane.swift` | ใหม่ | หน้า clipboard |
| `CoucouUsagePane.swift` | ใหม่ | การ์ด usage เลื่อนแนวนอน + รายละเอียด |
| `RiceMotion.swift` | ใหม่ | port physics จาก `brand/rice/motion.mjs` เป็น Swift (Foundation ล้วน) |
| `RiceMascotView.swift` | ใหม่ | `Canvas` + `TimelineView` วาดเมล็ดข้าว, gaze, กระพริบตา, squash |
| `CoucouAgentPane.swift` | แก้ | เพิ่ม `section` state; header และ body เปลี่ยนตาม section; gutter มี mascot + rail; **คง** geometry, `CardBackground`, `AgentPill`, decision controls เดิมทุกตัว |
| `IslandTypes.swift` (CoucouKit) | แก้ 1 บรรทัด | `.linkHub` layout: `botY` คงที่ (เฉพาะถ้าอนุมัติ D1) |
| `IslandRootView.swift` | แก้เล็กน้อย | ซ่อน bot หลักเมื่อ `.linkHub` ใน COUCOU_HUB (เฉพาะถ้าอนุมัติ D2) |
| `IslandWindowController.swift` | แก้ 1 บรรทัด | drag-enter ใน COUCOU_HUB: post `.coucouWorkspaceShowSection(.shelf)` ต่อจาก `hookExpand` ที่มีอยู่ |
| `FileDropView.swift` | ไม่แก้ | ใช้ `stageFiles` เดิม; comment "The UI designer will expose the shelf…" อัปเดตเป็นชี้ไปที่ Shelf pane |
| `CoucouHubIntegration.swift` | ไม่แก้ contract | อ่านอย่างเดียว ถ้าจำเป็นต้องมี published state ใหม่ จะถาม Codex ก่อน |

## 4. โครง workspace (ใช้ร่วมทุก section)

```
┌ gutter 84pt ┐┌──────────── content (width − 100) ────────────┐
│   ( rice )   ││ header 24pt: [section title / tabs] …  [✕]     │
│              ││────────────────────────────────────────────────│
│   [Agents]   ││ body: ความสูงคงที่ เลื่อนแนวตั้งภายในเท่านั้น      │
│   [Shelf  3] ││                                                │
│   [Clip   •] ││                                                │
│   [Usage]    ││                                                │
└──────────────┘└────────────────────────────────────────────────┘
```

- Header ของ Agents เหมือนเดิมทุกอย่าง (tabs 4 อัน + สถานะการเชื่อมต่อ + refresh/Manager/close)
- Header ของ section อื่น: ชื่อ section (11pt medium, `#F5F6F8`) + subtitle สั้น (`#8E939C`)
  + action เฉพาะ section ทางขวา (เช่น "Clear") + ปุ่ม close ตำแหน่งเดิม
- ทุก body ใช้ `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)` และ
  `.id(section)` + `.transition(.opacity)` แบบเดียวกับ tab เดิม — ข้อความยาวหรือชื่อ provider
  ยาวจะไม่ขยายกรอบ (ตามที่ test `agent selection cannot resize the host` ตรวจอยู่)
- ภาษาภาพ: ใช้ `CardBackground`, capsule row `#0E0F11` + stroke `white 0.05`, card radius 14,
  สีเดิม (`#F5F6F8`, `#C5C8CD`, `#8E939C`, `#6B7079`, amber `#F5A524`, red `#F4505E`,
  green `#22C55E`), `PrimaryButton` / `SecondaryButton`, เสียง `tick` / `blip` / `pop` ผ่าน
  `SoundEngine` (เคารพ toggle เสียง) — ไม่มี theme ใหม่ ไม่มี glass/glow เพิ่ม
- Animation: spring 0.3/0.8 ผ่าน helper `spring()` เดิมที่คืนค่า `nil` เมื่อ Reduce Motion เปิด
- Keyboard: rail เป็น focusable button, ⌘1–⌘4 สลับ section (เฉพาะตอน pane โฟกัส),
  `Esc` = collapse เหมือนเดิม

## 5. Shelf

**ข้อมูล:** `CoucouHubIntegration.shared.workspace.files` + `fileShelfError`

**Row (capsule สูง 30):** ไอคอนไฟล์จาก `NSWorkspace.shared.icon(forFile:)` 16pt · ชื่อไฟล์
(ตัดตรงกลาง) · ประเภท/ขนาด · เวลาที่เพิ่ม · ปุ่ม Reveal (`folder`) · ปุ่ม Remove (`xmark`)

**การกระทำ**
- **ลากออก:** `.onDrag { NSItemProvider(contentsOf: file.url) }` — ส่งไฟล์ต้นฉบับแบบ in-place
  ไม่ copy ไม่ย้าย
- **Reveal in Finder:** `NSWorkspace.shared.activateFileViewerSelecting([url])`
- **Remove:** `workspace.removeFile(id:)`; help text: "Remove from shelf. The original file stays where it is."
- **Clear shelf** (header): `workspace.clear()` ไม่ต้องยืนยันเพราะไม่ลบอะไรจริง แต่ข้อความบอกชัดว่าลบแค่รายการ
- **Send to agent:** ปุ่ม disabled + help "Sending to an agent isn't available yet." (แบบเดียวกับปุ่ม
  Wake) — ไม่มี routing ใหม่ ไม่มีการส่งเป็นผลข้างเคียงของการ drop

**สถานะ**

| สถานะ | สิ่งที่แสดง |
| --- | --- |
| ว่าง | notice: "Drop files on the notch to park them here. Originals stay where they are." |
| กำลังลากไฟล์เข้ามา (`state.fileDragOver`) | กรอบเส้นประ amber รอบ body + ข้อความ "Release to park" — mascot มองตามจุดลาก |
| ไฟล์หายไปแล้ว | ตรวจ `fileExists` ตอน pane ปรากฏ → row จาง, ป้าย "Missing", ปิดการลาก/Reveal, เหลือปุ่ม Remove |
| เต็ม (50) | แถบ amber: "Shelf is full (50). Remove a file to add more." จาก `shelfFull` |
| error อื่น (remote, not regular file, …) | แถบ red ด้วย `errorDescription` ของ backend |
| ไฟล์เยอะ | `ScrollView(.vertical)` ภายใน body; ตัวนับ "12 files" ใน header |

## 6. Clipboard

**ข้อมูล:** `CoucouHubIntegration.shared.clipboard`

**สถานะปิด (ค่าเริ่มต้น):** notice อธิบาย 3 บรรทัด
- "Clipboard history is off. Nothing is read until you turn it on."
- "History lives in memory only and is cleared when Coucou quits."
- "Coucou skips items that apps mark as concealed, but it can't spot passwords in ordinary text."

ปุ่ม: `PrimaryButton("Turn on history")` → `enableChangeMonitoring()` ·
`SecondaryButton("Capture current once")` → `captureManually()` (อ่านเฉพาะตอนผู้ใช้กด)

**สถานะเปิด:** header มี "Turn off" + "Clear"; รายการล่าสุดอยู่บนสุด (`history.reversed()`)

**Row (capsule หรือการ์ดเตี้ยสูง 34):**
- text → 2 บรรทัดแรก (ตัดที่ 160 ตัวอักษร), ไอคอน `text.alignleft`
- url → host + path, ไอคอน `link`
- image → thumbnail 28pt จาก PNG/TIFF data, ไอคอน `photo`
- fileReference → ชื่อไฟล์ + ไอคอนไฟล์
- เวลาที่เก็บ · ปุ่ม Copy · ปุ่ม Remove

**การกระทำ**
- **ลากไปแอปอื่น:** `.onDrag { snapshot.makeItemProviders().first }` — destination เลือก type ที่รับได้เอง
- **Copy (fallback):** `snapshot.recopy(to: .general)` แล้วแสดง "Copied" 1.2 วินาทีที่ row
  เมื่อ copy แล้ว capture รอบถัดไปจะเจอ changeCount ใหม่ → **ต้องข้าม** โดยจำ changeCount
  หลัง recopy ไว้ใน UI แล้วไม่ capture ซ้ำ (ถ้าทำไม่ได้โดยไม่แตะ backend จะยอมให้มีรายการซ้ำ
  และบันทึกเป็นข้อจำกัด / ขอ Codex เพิ่ม API)
- ไม่มีการพิมพ์/วางแทนผู้ใช้ ไม่มี global keystroke ไม่ต้องขอ Accessibility

**สถานะ**

| สถานะ | สิ่งที่แสดง |
| --- | --- |
| เปิดแต่ยังว่าง | "Copy something, then open the notch. Coucou checks while the notch is open." (ตาม D3) |
| ข้ามเพราะเป็นของลับ | แถบ amber: "Skipped one item the source app marked as private." |
| ใหญ่เกิน / item เยอะเกิน | แถบ amber ด้วยข้อความ backend (4 MB / 64 items) |
| ไม่มีชนิดที่รองรับ | ข้อความเทาเล็ก ไม่ใช่ error สีแดง |
| เต็ม 20 รายการ | อันเก่าหายเอง (backend) + ข้อความ "Keeps the latest 20." ใต้รายการ |

**จังหวะการตรวจ (D3):** `TimelineView(.periodic(from: .now, by: 1))` ภายใน pane ที่ทำงานเฉพาะ
เมื่อ history เปิด **และ** `state.mode != .hidden`; บวกการเรียก 1 ครั้งตอน island เปิด
ผ่าน `onChange(of: state.mode)` — ตอนซ่อนไม่มี timer ใดๆ เหลืออยู่

## 7. Usage

**ข้อมูล:** `CoucouUsageSnapshot.claude(state.claudePlanUsage)` คำนวณใหม่ทุก 30 วินาทีด้วย
`TimelineView(.periodic(..., by: 30))` แบบเดียวกับ `ClaudePlanCardView` + `state.planRelayInstalled`

**แถบการ์ด:** `ScrollView(.horizontal)` การ์ดกว้างคงที่ 150 × 96, radius 14, `#0E0F11`

| การ์ด | เนื้อหา |
| --- | --- |
| Claude Code — available | จุดสีตาม `ClaudePlanGauge.color`, "5 h" และ "Week" แต่ละอันเป็นแถบ 4pt + `used %`, บรรทัดล่าง "Updated 2 min ago" |
| Claude Code — stale | ค่าเดิมแต่จางลง 50%, ป้าย amber "Stale"; window ที่ reset ผ่านไปแล้วแสดง "Reset passed · waiting for new data" **ไม่แสดง 0%** (ไม่ใช้ `ClaudePlanGauge.effectivePct` ที่ปัดเป็น 0) |
| Claude Code — relay ปิด | "Statusline relay is off" + `SecondaryButton("Open Settings")` ไปหน้า settings ที่มีอยู่ (ไม่ติดตั้งให้เอง) |
| Claude Code — ติดตั้งแล้วแต่ยังไม่มีข้อมูล | "Waiting for a Claude Code reply" |
| Codex, Gemini CLI, Antigravity | "Unavailable — no supported usage source yet" สีเทา ไม่มีตัวเลข ไม่มี 0 |

**รายละเอียด (เปิดเมื่อกดการ์ด):** แผงความสูงคงที่ใต้แถบการ์ด แสดง
- Source: "Claude Code statusline relay (opt-in)"
- Observed: เวลาแบบ absolute + relative
- แต่ละ window: used %, remaining %, reset แบบ "Tue 14:00 · in 3 h 12 min" หรือ "passed"
- เหตุผลที่ stale: "Older than 15 min" หรือ "A reset time has passed"
- การ์ด unavailable: อธิบายว่ายังไม่มี API ที่รองรับ และ Coucou จะไม่อ่าน credential

ห้ามอ่าน credential หรือ scrape อะไรเพิ่ม — ใช้แค่ข้อมูลที่ relay ส่งมาอยู่แล้ว

## 8. Rice mascot

**Physics (`RiceMotion.swift`):** port ตรงจาก `brand/rice/motion.mjs` ซึ่งเป็นงาน original ของ
โปรเจกต์นี้
- `Spring(value, stiffness 170, damping 25)`; `to()` เก็บตำแหน่งและความเร็ว; step ย่อย ≤ 1/120 s,
  dt สูงสุด 50 ms
- 7 pose: idle, thinking, working, sending, approval, done, resting
- channel แยก: `cursorX` (±3), `cursorY` (±2), `press` (1 → 0.97, scaleX หารด้วย press เพื่อรักษาพื้นที่)
- breathing < 2%, ลอยขึ้นลง < 2 px, เอียงเล็กน้อยเมื่อ working
- เพิ่มใหม่ (ไม่มีใน prototype): channel `blink` (1 → 0.12 → 1), channel `squash`
  สำหรับ drop (sx 1.08 / sy 0.9 แล้ว rebound ด้วย spring เดิม — ขัดจังหวะได้)
- Reduce Motion: snap ทุก channel ไม่มี breathing/drift; pause: หยุดนาฬิกาโดยไม่กระตุก

**การวาด (`RiceMascotView.swift`):** `Canvas` วาด path cubic จาก `brand/rice/rice.svg` (ลำตัว, เส้น
highlight สองเส้น, ตาสองดวง `#7C5B28` ขอบ `#FFF1C6`), gradient `#FFFEF6 → #FFF2C7 → #D7A843`,
halo `#E8BC58` แบบ radial, ขนาดใน gutter 46–52pt — ไม่ใช้ path/expression/tween ของ Coucou หรือ Grok
`TimelineView(.animation(paused: state.mode == .hidden))` → 0% CPU ตอนซ่อน

**ความหมายของท่าทาง (map จากข้อมูลจริง ไม่เดา):**

| เหตุการณ์ | ท่า |
| --- | --- |
| ปกติ | idle |
| `model.heldRequestCount > 0` | approval (ตาเหลือบไปทาง Review) |
| มี agent `claimed > 0` | working |
| เชื่อมต่อ `offline` / `unpaired` | resting |
| drop ไฟล์เข้า shelf สำเร็จ | squash → rebound + done สั้นๆ 0.8 s แล้วกลับ |
| คำขอถูกตัดสินแล้ว (decision result) | done สั้นๆ |
| ลากไฟล์ค้างไว้เหนือ notch | ตามองตามจุดลาก |
| เมาส์อยู่ใกล้ | ตามองตามเมาส์ (`state.mousePosition`, จำกัด ±3/±2) |
| คลิก mascot | press + กระพริบตา 1 ครั้ง |
| สลับ section | ตาเหลือบไปทางปุ่ม rail ที่เลือกแล้วกลับ |
| idle นาน | กระพริบแบบสุ่ม 3–6 วินาที (ไม่ทำเมื่อ Reduce Motion) |

VoiceOver: mascot เป็น element เดียว label "Coucou" + value เป็นสถานะ ("2 requests waiting")

## 9. Tests ที่จะเพิ่ม

| ไฟล์ | สิ่งที่ตรวจ |
| --- | --- |
| `tests/RiceMotionTests.swift` + `scripts/test-rice-motion.sh` | เทียบ `motion.test.mjs`: retarget ต่อเนื่อง, กลับทิศเร็ว 100 ครั้งยังอยู่ในขอบเขต, ลู่เข้า, Reduce Motion snap, pause หยุดนิ่ง, blink/squash กลับค่าเดิม |
| `tests/CoucouWorkspacePresentationTests.swift` + `scripts/test-coucou-workspace-presentation.sh` | ข้อความการ์ด usage (fresh/stale/unavailable/relay off/reset passed ต้องไม่เป็น "0%"), เวลา relative, ขนาดไฟล์, การตัด preview, ชื่อ provider ยาว |
| `tests/CoucouHubIntegrationTests.mjs` (เพิ่ม case) | rail อยู่ใน gutter ไม่อยู่ใน header; Agents header ยังมีแค่ 4 tabs; ทุก section ใช้ `ScrollView(.vertical)` ภายใน body; usage ใช้ `ScrollView(.horizontal)`; clipboard ไม่เรียก `enableChangeMonitoring` นอก action ของปุ่ม; ไม่มี `effectivePct` ใน usage pane |

script ใหม่ compile ด้วย `swiftc -swift-version 6 -strict-concurrency=complete -D COUCOU_HUB`
แบบเดียวกับ `scripts/test-coucou-workspace-store.sh` — **ไม่แก้** test เดิมของ Codex ที่ผ่านอยู่

## 10. ลำดับการทำงาน

1. **Skeleton:** section enum + rail + gutter + header ที่สลับตาม section; Agents ทำงานเหมือนเดิม 100%
   → build + test เดิมต้องผ่านก่อนไปต่อ
2. **Shelf** + การเปิด Shelf อัตโนมัติตอนลากไฟล์เข้า notch
3. **Usage** + presentation helpers + tests
4. **Clipboard** + จังหวะตรวจตาม D3
5. **Rice mascot:** `RiceMotion` + tests → `RiceMascotView` → ต่อเข้ากับสถานะจริง
6. **Polish:** ดูด้วย lens `emil-design-eng` และ `apple-design` (ใช้เป็นมุมมองตรวจ ไม่ใช่บังคับทุกข้อ)
   และ `review-animations` สำหรับ mascot
7. **ตรวจทั้งหมด** (หัวข้อ 11) แล้วบันทึกผลใน `CODE_COACH_HANDOFF_RECEIPT.md`

แต่ละขั้น build `CoucouHub` Debug ก่อนไปขั้นถัดไป ไม่ commit/push จนกว่าเจ้าของสั่ง

## 11. การตรวจ

**อัตโนมัติ (ผมรันเองได้)**
```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme CoucouHub -configuration Debug build
```
- `scripts/test-coucou-workspace-store.sh`, `scripts/test-coucou-usage.sh`, `scripts/test-plan-gauge.sh`
- `node --test tests/CoucouHubIntegrationTests.mjs`, `node --test brand/rice/motion.test.mjs`
- script ใหม่สองตัวในหัวข้อ 9
- ยืนยันว่า build `NotchBuddy` (App Store) ยัง compile ได้และไม่มี diff ใน view ที่ ship แล้ว

**Live gate (ต้องให้เจ้าของอนุญาตก่อน)** — การรัน Debug build จะชนกับแอปที่ติดตั้งอยู่
(bundle id เดียวกัน, notch เดียวกัน) จึงต้องให้เจ้าของปิดแอปที่ติดตั้งไว้หรืออนุมัติให้รันชั่วคราว
ไม่มีการติดตั้งทับ
- สถานะ: ว่าง / ปิด / ถูกข้ามเพราะของลับ / เต็ม / stale / unavailable / relay ปิด
- ลากจริง: ไฟล์ → Finder, TextEdit, VS Code, ช่อง chat ของ Claude desktop; text/link/image →
  TextEdit, Notes; ทดสอบปุ่ม Copy เมื่อปลายทางไม่รับการลาก
- ชื่อ provider และข้อความยาวไม่ทำให้กรอบเปลี่ยนขนาด
- Keyboard, VoiceOver, Reduce Motion
- จับภาพ panel จริงด้วย `screencapture` ไว้ใน `design/captures/` ไม่ใช่ภาพ fixture
- บันทึกเฉพาะปลายทางที่ลองจริงเท่านั้น ที่ไม่ได้ลองจะเขียนว่ายังไม่ได้ทดสอบ

## 12. นอกขอบเขต / ไม่แตะ

routing ของ agent, credential/Keychain, signing และ bundle identity (`com.hubisland.desktop`), hooks,
`~/.claude/settings.json`, permissions, อำนาจการ approve, policy ของ backend, การสร้าง media,
push/release, การติดตั้งแอป, view ที่ ship แล้วใน `main`, `brand/rice/*` (อ่านอย่างเดียว),
ไฟล์ของ agent อื่นที่ยังไม่ commit (แก้เฉพาะจุดที่ระบุในหัวข้อ 3)

## 13. ความเสี่ยง

- **ไฟล์ร่วมกับ Codex:** `IslandWindowController.swift` และ `CoucouAgentPane.swift` มีงานค้างของคนอื่น
  → แก้แบบเพิ่มเฉพาะจุด ตรวจ `git diff` ก่อนและหลัง
- **ลากหลายรายการ:** SwiftUI `.onDrag` ส่งได้ทีละ provider — v1 ลากได้ทีละไฟล์/ทีละรายการ
  การลากหลายไฟล์พร้อมกันต้องใช้ `NSDraggingSource` (เฟสถัดไป)
- **ซ้ำหลัง Copy:** ดูหัวข้อ 6
- **พื้นที่ gutter:** ถ้าไม่อนุมัติ D1 ต้องหาตำแหน่ง rail ใหม่ก่อนเริ่มขั้น 1
