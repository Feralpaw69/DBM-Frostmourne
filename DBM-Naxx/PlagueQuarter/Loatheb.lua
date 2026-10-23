local mod	= DBM:NewMod("Loatheb", "DBM-Naxx", 3)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20221022102923")
mod:SetCreatureID(16011)

mod:RegisterCombat("combat")--Maybe change to a yell later so pull detection works if you chain pull him from tash gauntlet

mod:RegisterEventsInCombat(
	"SPELL_CAST_SUCCESS 29204 55052 55593 9250601 9250605 9250600 9250604",
	"SPELL_AURA_APPLIED 9250692",
	"SPELL_AURA_REMOVED 9250692",
	"SPELL_DAMAGE",
	"SPELL_SUMMON 29234",
	"SWING_DAMAGE",
	"UNIT_DIED"
)

--TODO, verify infoframe and spellIds ported from Classic as accurate, they didn't have to be accurate in classic since it just matched name, but here it does
--Also, 55593 is used instead of classic ID since classic ID has no tooltip
local warnSporeNow	= mod:NewCountAnnounce(32329, 2)
local warnSporeSoon	= mod:NewSoonAnnounce(32329, 1)
local warnDoomNow	= mod:NewSpellAnnounce(29204, 3)
local warnHealSoon	= mod:NewAnnounce("WarningHealSoon", 4, 48071, nil, nil, nil, 55593)
local warnHealNow	= mod:NewAnnounce("WarningHealNow", 1, 48071, false, nil, nil, 55593)

local timerSpore	= mod:NewNextTimer(15, 32329, nil, nil, nil, 5, 42524, DBM_COMMON_L.DAMAGE_ICON)
local timerDoom		= mod:NewNextTimer(20, 29204, nil, nil, nil, 2)
local timerAura		= mod:NewBuffActiveTimer(17, 55593, nil, nil, nil, 5, nil, DBM_COMMON_L.HEALER_ICON)
-- Frostmourne custom (482s kill logged 2026-10-06)
local warnVolatile		= mod:NewTargetNoFilterAnnounce(9250692, 3)
local specWarnVolatile	= mod:NewSpecialWarningYou(9250692, nil, nil, nil, 1, 2)
local timerDeathbloom	= mod:NewNextTimer(30, 9250605, nil, nil, nil, 2) -- 5.0, then every 30.0
local timerVolatileCD	= mod:NewNextTimer(15, 9250692, nil, nil, nil, 3) -- Volatile Spores: 15.1, then every 15.1
local timerVolatile		= mod:NewTargetTimer(10, 9250692, nil, nil, nil, 5) -- explodes when it ends, 10s later
local yellVolatile		= mod:NewYell(9250692, "Volatile Spore on me! Move to Shroom.")

mod:SetUsedIcons(8, 7)
mod:AddSetIconOption("SetIconOnVolatile", 9250692, true, false, {8, 7})
local volatileIcon = 8

mod:AddBoolOption("SporeDamageAlert", false)
-- Volatile Spores explode for 9250694 on the carrier when the 10s run out (logs: every carrier takes it). If that hit
-- kills the carrier, Spore Catastrophe (9250695) hits the whole raid. Only the direct 9250694 death is reported here,
-- by the player who died (needs this DBM version on that player).
mod:AddBoolOption("VolatileDeathMsg", true)
DBM:GetModLocalization("Loatheb"):SetOptionLocalization({VolatileDeathMsg = "Say in raid chat \"I died to Volatile Spore and wiped the Raid :(\" when the Volatile Spore explosion kills you"})
local function CheckVolatileDeath(self)
	if UnitIsDeadOrGhost("player") and self:AntiSpam(10, "VolatileDeath") then
		SendChatMessage("I died to Volatile Spore and wiped the Raid :(", GetNumRaidMembers() > 0 and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or "SAY"))
	end
end

mod.vb.doomCounter	= 0
mod.vb.sporeTimer	= 15
mod.vb.sporeCounter = 0
local pullTime = 0

function mod:OnCombatStart(delay)
	pullTime = GetTime() - delay
	self.vb.doomCounter = 0
	self.vb.sporeCounter = 0
	if self:IsDifficulty("normal25") then
		self.vb.sporeTimer = 15
		timerDoom:Start(20 - delay, 1)
	else
		self.vb.sporeTimer = 36
		timerDoom:Start(120 - delay, 1)
	end
	if self:IsDifficulty("heroic25") then -- Frostmourne raid reports as heroic25: spores at 18.0, then every 15.0-15.1
		self.vb.sporeTimer = 15
	end
	timerDeathbloom:Start(5 - delay)
	timerVolatileCD:Start(15 - delay)
	timerSpore:Start(18 - delay, 1)
	warnSporeSoon:Schedule(18 - 5 - delay)
end

function mod:SPELL_SUMMON(args)
	if args.spellId == 29234 then -- Summon Spore
		self.vb.sporeCounter = self.vb.sporeCounter + 1
		timerSpore:Start(self.vb.sporeTimer, self.vb.sporeCounter + 1)
		warnSporeNow:Show(self.vb.sporeCounter)
		warnSporeSoon:Schedule(self.vb.sporeTimer - 5)
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	local spellId = args.spellId
	if args:IsSpellID(29204, 55052, 9250601, 9250600) then -- 9250600: 10-man  -- Inevitable Doom (9250601: Frostmourne custom)
		self.vb.doomCounter = self.vb.doomCounter + 1
		warnDoomNow:Show(self.vb.doomCounter)
		if self:IsDifficulty("normal25") then
			timerDoom:Start(20, self.vb.doomCounter + 1)
		elseif GetTime() - pullTime > 295 then -- log: first at 120, every 30 until 300s, then every 15
			timerDoom:Start(15, self.vb.doomCounter + 1)
		else
			timerDoom:Start(30, self.vb.doomCounter + 1)
		end
	elseif spellId == 9250605 or spellId == 9250604 then -- Deathbloom (9250604: 10-man)
		timerDeathbloom:Start()
	elseif spellId == 55593 then
		timerAura:Start()
		warnHealSoon:Schedule(14)
		warnHealNow:Schedule(17)
	end
end

--Spore loser function. Credits to Forte guild and their old discontinued dbm plugins. Sad to see that guild disband, best of luck to them!
function mod:SPELL_DAMAGE(_, sourceName, _, destGUID, destName, _, spellId, _, _, amount, overkill)
	if spellId == 9250694 and destGUID == UnitGUID("player") and self.Options.VolatileDeathMsg then -- Volatile Spores explosion hit me
		self:Schedule(0.3, CheckVolatileDeath, self) -- check right after the hit whether it killed me
		return
	end
	if self.Options.SporeDamageAlert and destName == "Spore" and spellId ~= 62124 and self:IsInCombat() then
		SendChatMessage(sourceName..", You are damaging a Spore!!! ("..amount.." damage)", "RAID_WARNING")
		SendChatMessage(sourceName..", You are damaging a Spore!!! ("..amount.." damage)", "WHISPER", nil, sourceName)
	end
end

function mod:SWING_DAMAGE(_, sourceName, _, _, destName, _, _, _, _, amount)
	if self.Options.SporeDamageAlert and destName == "Spore" and self:IsInCombat() then
		SendChatMessage(sourceName..", You are damaging a Spore!!! ("..amount.." damage)", "RAID_WARNING")
		SendChatMessage(sourceName..", You are damaging a Spore!!! ("..amount.." damage)", "WHISPER", nil, sourceName)
	end
end

--because in all likelyhood, pull detection failed (cause 90s like to charge in there trash and all and pull it
--We unschedule the pre warnings on death as a failsafe
function mod:UNIT_DIED(args)
	local cid = self:GetCIDFromGUID(args.destGUID)
	if cid == 16011 then
		timerDeathbloom:Cancel()
		timerVolatileCD:Cancel()
		warnSporeSoon:Cancel()
		warnHealSoon:Cancel()
		warnHealNow:Cancel()
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 9250692 then -- Volatile Spores
		timerVolatileCD:Start()
		timerVolatile:Start(args.destName)
		if self.Options.SetIconOnVolatile then -- skull, then cross if a second one is out at the same time
			self:SetIcon(args.destName, volatileIcon, 10)
			volatileIcon = volatileIcon == 8 and 7 or 8
		end
		if args:IsPlayer() then
			specWarnVolatile:Show()
			specWarnVolatile:Play("targetyou")
			yellVolatile:Yell()
		else
			warnVolatile:Show(args.destName)
		end
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == 9250692 then
		timerVolatile:Stop(args.destName)
		if self.Options.SetIconOnVolatile then
			self:SetIcon(args.destName, 0)
		end
	end
end
