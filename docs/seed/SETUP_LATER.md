# Seed: สิ่งที่ต้อง set up ทีหลัง (จด 2026-10-07)

ยังไม่ได้ทำ เก็บไว้ทำตอนพร้อม ทุกข้อทำจาก Seed → menu bar → Settings… → **Agents**

## 1. ให้ Seed อ่านทีม agent จาก Tincan
- ตอนเปิดหน้า Agents ครั้งแรก ถ้า macOS ถามสิทธิ์ Keychain ให้กด **Allow**
- การ์ด "Your agent team" ควรขึ้นจำนวน agent ที่ online และรายชื่อ (codex, claude-code, cursor, opencode …)
- ถ้าขึ้น **Not set up / Read-only / Access denied**: ต้องให้ credential ของ LinkHub ที่มีสิทธิ์ Tincan operator
  ผ่าน trusted installer ใน `agent-linkhub` (`agent_hub/island_install.py`, เปิด Tincan approval)
  หมายเหตุ: installer ตอนนี้รับเฉพาะ `HubIsland.app` (bundle `com.hubisland.desktop`) ส่วน Seed อ่าน Keychain item ตัวเดียวกัน
  → งานของ Codex: ให้ installer รองรับ `Seed.app` (`com.grunte.seed`) ด้วย
- ถ้าขึ้น **LinkHub offline**: เปิด LinkHub (`agent_hub.cli serve … --manager-port 8768`) แล้วกด Refresh

## 2. ต่อ hook ให้ agent ในเครื่อง (สถานะสด + การ์ดขออนุญาตที่ notch)
ตอนตรวจ (2026-10-07) ยังไม่มี hook ติดตั้งเลย
- **Claude Code:** Connect → อ่าน JSON → Write → เริ่ม session ใหม่
- **Codex:** Connect → Write → เปิด Codex พิมพ์ `/hooks` แล้ว trust hook ของ Seed
- **Gemini CLI / Antigravity:** Connect → Write → รีสตาร์ตแอปนั้น
- ทุกข้อจะโชว์ JSON ก่อน และไม่มีอะไรถูกเขียนจนกว่าจะกด Write
- Seed กับ Coucou ใช้ socket เดียวกัน (`~/Library/Application Support/NotchBuddy/nb.sock`) ห้ามเปิดพร้อมกัน

## 3. แท็บ Usage (โควตา Claude)
- Plan usage → Install → อ่าน JSON → Write (เพิ่ม status line relay ใน `~/.claude/settings.json`)

## 4. เพิ่ม agent ใหม่เข้าทีม (ถ้าต้องการ)
- Add an agent → ใส่ชื่อ + เลือกชนิด → Create invite → Copy → วางใน agent ภายใน 10 นาที
- ปุ่มนี้สร้าง invite จริงบน relay ในเครื่อง (ใช้ admin socket ที่ LinkHub ใช้อยู่)

## งานหลังบ้านที่ส่งต่อให้ Codex
- installer ของ LinkHub รองรับ Seed.app (ข้อ 1)
- แผน 005: Seed MCP server (`seed.describe`, `seed.add_shortcut` …) ดู `docs/seed/SEED_SKILL.md`
- ชื่อ Keychain service ของ Seed (ตอนนี้ยังใช้ `com.hubisland.desktop` ร่วม)
- สคริปต์ sign Seed.app สำหรับติดตั้งจริง
- เหตุการณ์ "thinking" และ "sending" ของ agent (ตอนนี้ไม่มีข้อมูลจริง Seed เลยยังไม่ใช้ท่าทั้งสอง)
