-- ALSA buffer tuning for PipeWire/WirePlumber
--
-- Adds headroom to all ALSA nodes to prevent broken-pipe (XRUN) errors.
-- Root cause: USB audio devices (BTD-800 dongle) and HDMI/S/PDIF outputs
-- have no jitter buffering in PipeWire's SPA ALSA plugin. Under load,
-- the playback stream hits XRUN and enters an unrecoverable error loop.
--
-- 1536 frames = ~32ms headroom at 48kHz. Negligible for calls/music.

rule = {
  matches = {
    {
      { "node.name", "matches", "alsa_output.*" },
    },
    {
      { "node.name", "matches", "alsa_input.*" },
    },
  },
  apply_properties = {
    ["api.alsa.headroom"]    = 1536,
    ["api.alsa.period-size"] = 1024,
  },
}

table.insert(alsa_monitor.rules, rule)
