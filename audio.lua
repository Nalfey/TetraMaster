sounds = {}

local SFX_PATH = "assets/sound/wav/"
local MUSIC_PATH = "assets/sound/"
local MUSIC_VOLUME = 0.45 * 0.7
local SFX_VOLUME = 0.4

local sfx_files = {
  card_battle = "snd_card_battle.wav",
  choose_card = "snd_choose_card.wav",
  combo_woosh = "snd_combo_woosh.wav",
  cursor = "snd_cursor.wav",
  error = "snd_error.wav",
  escape = "snd_escape.wav",
  flip_card = "snd_flip_card.wav",
  lose_card = "snd_lose_card.wav",
  put = "snd_put.wav",
  splash_screen = "snd_splash_screen.wav",
  win_card = "snd_win_card.wav",
}

local end_game_mp3 = {
  win_game = "snd_win_game.mp3",
  lose_game = "snd_lose_game.mp3",
  tie_game = "snd_tie_game.mp3",
  perfect_game = "snd_perfect_game.mp3",
}

function init_audio()
  for name, file in pairs(sfx_files) do
    local source = love.audio.newSource(SFX_PATH .. file, "static")
    source:setVolume(SFX_VOLUME)
    sounds[name] = source
  end

  sounds.coin = love.audio.newSource(MUSIC_PATH .. "snd_coin.mp3", "static")
  sounds.coin:setVolume(SFX_VOLUME)

  for name, file in pairs(end_game_mp3) do
    local source = love.audio.newSource(MUSIC_PATH .. file, "static")
    source:setVolume(SFX_VOLUME)
    sounds[name] = source
  end

  sounds.music = love.audio.newSource(MUSIC_PATH .. "mus_quadmist.mp3", "stream")
  sounds.music:setLooping(true)
  sounds.music:setVolume(MUSIC_VOLUME)
end

function play_sound(name)
  local source = sounds[name]
  if source then
    source:stop()
    source:play()
  end
end

function play_music()
  if sounds.music and not sounds.music:isPlaying() then
    sounds.music:play()
  end
end

function stop_music()
  if sounds.music then
    sounds.music:stop()
  end
end

function play_capture_sound(new_owner)
  if new_owner == "blue" then
    play_sound("win_card")
  elseif new_owner == "red" then
    play_sound("lose_card")
  end
end
