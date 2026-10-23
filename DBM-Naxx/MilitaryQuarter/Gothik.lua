local mod	= DBM:NewMod("Gothik", "DBM-Naxx", 4)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20220629223621")
mod:SetCreatureID(16060)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_CAST_SUCCESS 9250700 9250699",
	"SPELL_AURA_APPLIED 9250700 9250699",
	"UNIT_DIED"
)

--TODO, sync infoframe from classic era version?
--(source.type = "NPC" and source.firstSeen = timestamp) or (target.type = "NPC" and target.firstSeen = timestamp)
local warnWaveNow		= mod:NewAnnounce("WarningWaveSpawned", 3, nil, false)
local warnWaveSoon		= mod:NewAnnounce("WarningWaveSoon", 2)
local warnRiderDown		= mod:NewAnnounce("WarningRiderDown", 4)
local warnKnightDown	= mod:NewAnnounce("WarningKnightDown", 2)
local warnPhase2		= mod:NewPhaseAnnounce(2, 3)

local timerPhase2		= mod:NewTimer(270, "TimerPhase2", 27082, nil, nil, 6)
local timerWave			= mod:NewTimer(20, "TimerWave", 5502, nil, nil, 1)
local timerGate			= mod:NewTimer(150, "Gate Opens", 9484)
local timerTeleport		= mod:NewTimer(25, "TimerTeleport", 31569)
local timerSoulConvergence = mod:NewNextTimer(30, 9250700, nil, nil, nil, 2) -- Frostmourne custom, logs 2026-10-06: 30.0, then every 30.0 (two pulls)

mod:SetUsedIcons(1, 2, 3, 4, 5, 6, 7, 8)
mod:AddSetIconOption("SetIconOnConvergence", 9250700, true, false, {1, 2, 3, 4, 5, 6, 7, 8})

local convergenceIcon = 1
mod.vb.wave = 0
local wavesNormal = {
	{2, L.Trainee, timer = 20},
	{2, L.Trainee, timer = 20},
	{2, L.Trainee, timer = 10},
	{1, L.Knight, timer = 10},
	{2, L.Trainee, timer = 15},
	{1, L.Knight, timer = 5},
	{2, L.Trainee, timer = 20},
	{1, L.Knight, 2, L.Trainee, timer = 10},
	{1, L.Rider, timer = 10},
	{2, L.Trainee, timer = 5},
	{1, L.Knight, timer = 15},
	{2, L.Trainee, 1, L.Rider, timer = 10},
	{2, L.Knight, timer = 10},
	{2, L.Trainee, timer = 10},
	{1, L.Rider, timer = 5},
	{1, L.Knight, timer = 5},
	{2, L.Trainee, timer = 20},
	{1, L.Rider, 1, L.Knight, 2, L.Trainee, timer = 15},
	{2, L.Trainee},
}

local wavesHeroic = {
	{3, L.Trainee, timer = 20},
	{3, L.Trainee, timer = 20},
	{3, L.Trainee, timer = 10},
	{2, L.Knight, timer = 10},
	{3, L.Trainee, timer = 15},
	{2, L.Knight, timer = 5},
	{3, L.Trainee, timer = 20},
	{3, L.Trainee, 2, L.Knight, timer = 10},
	{3, L.Trainee, timer = 10},
	{1, L.Rider, timer = 5},
	{3, L.Trainee, timer = 15},
	{1, L.Rider, timer = 10},
	{2, L.Knight, timer = 10},
	{1, L.Rider, timer = 10},
	{1, L.Rider, 3, L.Trainee, timer = 5},
	{1, L.Knight, 3, L.Trainee, timer = 5},
	{1, L.Rider, 3, L.Trainee, timer = 20},
	{1, L.Rider, 2, L.Knight, 3, L.Trainee},
}

local waves = wavesNormal

local NextWave -- defined below

local function StartPhase2(self)
	self:SetStage(2)
	self:Unschedule(NextWave) -- no more waves once Gothik is down
	timerWave:Stop()
	warnWaveSoon:Cancel()
	if self:IsDifficulty("normal25") then
		timerTeleport:Start()
	else
		timerTeleport:Start(20)
	end
end

local function getWaveString(wave)
	local waveInfo = waves[wave]
	if #waveInfo == 2 then
		return L.WarningWave1:format(unpack(waveInfo))
	elseif #waveInfo == 4 then
		return L.WarningWave2:format(unpack(waveInfo))
	elseif #waveInfo == 6 then
		return L.WarningWave3:format(unpack(waveInfo))
	end
end

function NextWave(self)
	self.vb.wave = self.vb.wave + 1
	warnWaveNow:Show(self.vb.wave, getWaveString(self.vb.wave))
	local timer = waves[self.vb.wave].timer
	if timer then
		timerWave:Start(timer, self.vb.wave + 1)
		warnWaveSoon:Schedule(timer - 3, self.vb.wave + 1, getWaveString(self.vb.wave + 1))
		self:Schedule(timer, NextWave, self)
	end
end

function mod:OnCombatStart()
	self:SetStage(1)
	if self:IsDifficulty("normal25") then
		waves = wavesHeroic
	else
		waves = wavesNormal
	end
	self.vb.wave = 0
	-- Frostmourne raid reports as heroic25; logs 2026-10-06: Gothik's first cast at 181.9 in both pulls (was 270)
	local p2 = self:IsDifficulty("heroic10", "heroic25") and 180 or 270 -- 10-man log 2026-10-08: also 180
	timerSoulConvergence:Start(30)
	timerGate:Start()
	timerPhase2:Start(p2)
	warnPhase2:Schedule(p2)
	timerWave:Start(25, self.vb.wave + 1)
	warnWaveSoon:Schedule(22, self.vb.wave + 1, getWaveString(self.vb.wave + 1))
	self:Schedule(25, NextWave, self)
	self:Schedule(p2, StartPhase2, self)
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(9250700, 9250699) then -- Soul Convergence (Frostmourne custom; 9250699: 10-man)
		timerSoulConvergence:Start()
	end
end

function mod:OnTimerRecovery()
	if self:IsDifficulty("normal25") then
		waves = wavesHeroic
	else
		waves = wavesNormal
	end
end

function mod:UNIT_DIED(args)
	if bit.band(args.destGUID:sub(0, 5), 0x00F) == 3 then
		local cid = self:GetCIDFromGUID(args.destGUID)
		if cid == 16126 then -- Unrelenting Rider
			warnRiderDown:Show()
		elseif cid == 16125 then -- Unrelenting Deathknight
			warnKnightDown:Show()
		end
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpellID(9250700, 9250699) and self.Options.SetIconOnConvergence then -- Soul Convergence: mark every target of this cast
		if self:AntiSpam(5, "ConvergenceIcon") then
			convergenceIcon = 1
		end
		if convergenceIcon <= 8 then
			self:SetIcon(args.destName, convergenceIcon, 8)
		end
		convergenceIcon = convergenceIcon + 1
	end
end
