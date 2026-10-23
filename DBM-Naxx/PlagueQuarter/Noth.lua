local mod	= DBM:NewMod("Noth", "DBM-Naxx", 3)
local L		= mod:GetLocalizedStrings()

local GetSpellInfo = GetSpellInfo

mod:SetRevision("20221027184343")
mod:SetCreatureID(15954)

mod:RegisterCombat("combat_yell", L.Pull)

mod:RegisterEvents(
	"SPELL_CAST_SUCCESS 29213 54835 9250591 9250590",
	"SPELL_AURA_APPLIED 29208 29209 29210 29211 9250589 9250588 9250688 9250689 9250690",
	"SPELL_AURA_REFRESH 9250688 9250689 9250690",
	"SPELL_AURA_REMOVED 9250688 9250689 9250690",
	"SPELL_CAST_START 54890 54891",
	"CHAT_MSG_RAID_BOSS_EMOTE"
)

local emote_Teleport = "%s teleports to the balcony above!"
local emote_Return = "%s teleports back into the battle!"

local warnTeleportNow	= mod:NewAnnounce("WarningTeleportNow", 3, 46573)
local warnTeleportSoon	= mod:NewAnnounce("WarningTeleportSoon", 1, 46573)
local warnCurse			= mod:NewSpellAnnounce(29213, 2)
local warnBlinkSoon		= mod:NewSoonAnnounce(29208, 1)
local warnBlink			= mod:NewSpellAnnounce(29208, 3)

local specWarnAdds		= mod:NewSpecialWarningAdds(29212, "-Healer", nil, nil, 1, 2)
local specWarnExplosion	= mod:NewSpecialWarningInterrupt(54891)
local specWarnDecurse	= mod:NewSpecialWarningDispel(29213, "RemoveCurse", nil, nil, 1, 2)
local specWarnWrath		= mod:NewSpecialWarningSpell(9250589, nil, nil, nil, 2, 2) -- Frostmourne custom

local timerTeleport		= mod:NewTimer(80, "TimerTeleport", 46573, nil, nil, 6)
local timerTeleportBack	= mod:NewTimer(70, "TimerTeleportBack", 46573, nil, nil, 6)
local timerCurseCD		= mod:NewCDTimer(25, 29213, nil, nil, nil, 5, nil, DBM_COMMON_L.CURSE_ICON) -- Whitemane PTR - buff notes say 15s, vod says consistent 25s
local timerAddsCD		= mod:NewAddsTimer(25, 29212, nil, "-Healer")
local timerBlink		= mod:NewNextTimer(30, 29208)

mod:SetUsedIcons(1, 2, 3, 4, 5, 6, 7, 8)
mod:AddSetIconOption("SetIconOnResidue", 9250688, true, false, {8, 7, 6, 5, 4, 3, 2, 1})
-- Plague Residue (Frostmourne custom; 9250688 on the player whose curse was removed, then 9250690 (25) / 9250689 (10)
-- on the players it spreads to). Not Curse of the Plaguebringer. Every player with the debuff is marked the moment
-- it lands (skull first, then the next free icon) and unmarked when it fades; 8s safety clear.
local residueMarks = {}	-- [name] = icon
local function FreeResidueIcon(self, name)
	local icon = name and residueMarks[name]
	if icon then
		residueMarks[name] = nil
		self:SetIcon(name, 0)
	end
end
local function MarkResidue(self, name)
	if not name then return end
	self:Unschedule(FreeResidueIcon, self, name)
	if not residueMarks[name] then
		local used = {}
		for _, i in pairs(residueMarks) do used[i] = true end
		local icon
		for i = 8, 1, -1 do
			if not used[i] then icon = i break end
		end
		if not icon then return end -- all 8 icons in use
		residueMarks[name] = icon
		self:SetIcon(name, icon)
	end
	self:Schedule(8, FreeResidueIcon, self, name)
end
local timerWrath		= mod:NewCastTimer(10, 9250589, nil, nil, nil, 2, nil, DBM_COMMON_L.CURSE_ICON) -- Frostmourne custom, log 2026-10-06: hits 10.0s after a Curse that was not removed


function mod:OnCombatStart(delay)
	timerAddsCD:Start(-delay)
	timerCurseCD:Start(15-delay)
	if self:IsDifficulty("normal25", "heroic25") then -- Frostmourne raid reports as heroic25 and Noth blinks there (log 2026-10-06)
		timerBlink:Start(26-delay)
		warnBlinkSoon:Schedule(23-delay)
	end
	timerTeleport:Start(-delay)
	warnTeleportSoon:Schedule(70-delay)
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(29213, 54835, 9250591, 9250590) then -- 9250590: 10-man -- Curse of the Plaguebringer (9250591: Frostmourne custom)
		warnCurse:Show()
		timerCurseCD:Start()
		if args:IsSpellID(9250591, 9250590) then
			timerWrath:Start()
		end
		if self.Options.SpecWarn29213dispel and UnitPowerType("player") == 0 then -- crudely filter out feral druids
			specWarnDecurse:Show("raid")
			specWarnDecurse:Play("helpdispel")
		end
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if self:IsDifficulty("normal25", "heroic25") and args:IsSpellID(29208, 29209, 29210, 29211) then -- Blink
		warnBlink:Show()
		timerBlink:Start()
		warnBlinkSoon:Schedule(27)
	elseif args:IsSpellID(9250589, 9250588) and self:AntiSpam(3, "Wrath") then -- Wrath of the Plaguebringer (Frostmourne custom)
		timerWrath:Stop()
		specWarnWrath:Show()
		specWarnWrath:Play("aesoon")
	elseif args:IsSpellID(9250688, 9250689, 9250690) and self.Options.SetIconOnResidue and args:IsDestTypePlayer() then -- Plague Residue
		MarkResidue(self, args.destName)
	end
end
mod.SPELL_AURA_REFRESH = mod.SPELL_AURA_APPLIED

function mod:SPELL_AURA_REMOVED(args)
	if args:IsSpellID(9250688, 9250689, 9250690) and residueMarks[args.destName] then
		local name = args.destName
		-- the 10/25 residue can follow right after 9250688 on the same player: wait a moment before unmarking
		self:Unschedule(FreeResidueIcon, self, name)
		self:Schedule(0.5, FreeResidueIcon, self, name)
	end
end

function mod:OnCombatEnd()
	for name in pairs(residueMarks) do
		self:SetIcon(name, 0)
		residueMarks[name] = nil
	end
end

function mod:SPELL_CAST_START(args)
	if args:IsSpellID(54890, 54891) and self:AntiSpam(1, "ArcaneExplosion") then -- Arcane Explosion
		specWarnExplosion:Show(args.sourceName)
	end
end

function mod:CHAT_MSG_RAID_BOSS_EMOTE(msg) -- Syncing to help unlocalized clients
	if msg == emote_Teleport or msg:find(emote_Teleport) then
		self:SendSync("Teleport")
	elseif msg == emote_Return or msg:find(emote_Return) then
		self:SendSync("Return")
	elseif msg == L.Adds or msg:find(L.Adds) then
		self:SendSync("Adds")
	elseif msg == L.AddsTwo or msg:find(L.AddsTwo) then
		self:SendSync("AddsTwo")
	end
end

function mod:OnSync(msg)
	if not self:IsInCombat() then return end
	if msg == "Teleport" then -- Teleport away
		timerCurseCD:Stop()
		timerWrath:Stop()
		timerAddsCD:Start(4)
		timerBlink:Stop()
		warnBlinkSoon:Cancel()
		timerTeleportBack:Start()
		warnTeleportSoon:Schedule(70 - 10)
		warnTeleportNow:Show()
	elseif msg == "Return" then -- Return to ground
		warnTeleportNow:Show()
		timerAddsCD:Start()
		timerCurseCD:Start(15)
		if self:IsDifficulty("normal25", "heroic25") then
			timerBlink:Start(26)
			warnBlinkSoon:Schedule(23)
		end
		timerTeleport:Start()
		warnTeleportSoon:Schedule(70)
	elseif msg == "Adds" then -- Boss Grounded
		specWarnAdds:Show()
		specWarnAdds:Play("killmob")		
		timerAddsCD:Start()
	elseif msg == "AddsTwo" then -- Boss away
		specWarnAdds:Show()
		specWarnAdds:Play("killmob")
		timerAddsCD:Start()
	end
end
