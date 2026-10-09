# Seed sounds

Seed's UI sounds live in `NotchBuddy/Resources/Seed/sounds/`. They are bundled into the Seed and SeedLab targets only. Coucou's `Resources/sounds/` stays as a reference and is not used by Seed.

## Source
- Generated with ElevenLabs `eleven_text_to_sound_v2` in the owner's flow "Seed UI sounds v1": https://elevenlabs.io/app/flows/BdnNp7SXmT3v5hNm0Pus
- Prompt influence 0.6.
- Each prompt was generated twice: variant a and variant b.
- Tone: warm, soft and bright (glass bell, ceramic, light wood).

## Processing (2026-10-07)
- Left channel only, 44.1 kHz, mono, 16-bit PCM WAV.
- Silence trimmed at -50 dB (tick at -62 dB).
- 3 ms fade-in and 40 ms fade-out.
- Each file's peak is matched to the peak of the Coucou sound with the same name, so loudness stays in balance under `SoundEngine`'s volume 0.12. Boost is capped at +18 dB.

## Which variant feeds which name

| Name | Source |
|---|---|
| tick, blip, error, approve, peek, finish, approval, work, send, rate, open, close, love, hover, greeting | their own variant a |
| pop | pop b (pop a is almost silent) |
| question | approval b |
| attach | pop b |
| greet | greeting b |
| think | work b |
| search | blip b |
| proud | finish b |
| wink | love b |
| sleep | close b |

## Not produced
These are Mochi-only reactions and are silent in Seed:
- slap
- annoyed
- dizzy
- gulp
- yawn

## Redo or swap a sound
Pick another generation in the flow, download it, and run the same ffmpeg chain:

```
pan=mono|c0=c0, silenceremove …, areverse …, afade
```

Then apply `volume=<ref peak − new peak>dB`.
