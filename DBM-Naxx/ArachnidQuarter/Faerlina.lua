local mod	= DBM:NewMod("Faerlina", "DBM-Naxx", 1)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20221016190115")
mod:SetCreatureID(15953)

mod:RegisterCombat("combat_yell", L.Pull)

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 28798 54100 28732 54097 28794 54099 9250587 9250586",
	"SPELL_CAST_SUCCESS 28796 54098 9250585 9250587 9250687 9250584 9250586 9250686",
	"CHAT_MSG_RAID_BOSS_EMOTE",
	"UNIT_DIED"
)

local warnEmbraceActive		= mod:NewSpellAnnounce(28732, 1)
local warnEmbraceExpire		= mod:NewAnnounce("WarningEmbraceExpire", 2, 28732, nil, nil, nil, 28732)
local warnEmbraceExpired	= mod:NewFadesAnnounce(28732, 3)
local warnEnrageSoon		= mod:NewSoonAnnounce(28131, 3)
local warnEnrageNow			= mod:NewSpellAnnounce(28131, 4)

local specWarnEnrage		= mod:NewSpecialWarningDefensive(28131, nil, nil, nil, 3, 2)
local specWarnGTFO			= mod:NewSpecialWarningGTFO(28794, nil, nil, nil, 1, 8)
local specWarnRisen			= mod:NewSpecialWarning("SpecWarnRisenWorshipper", nil, nil, nil, 1, 2) -- Frostmourne custom: a dead Worshipper rises about 6s later
DBM:GetModLocalization("Faerlina"):SetWarningLocalization({SpecWarnRisenWorshipper = "Risen Worshipper!"})
DBM:GetModLocalization("Faerlina"):SetOptionLocalization({SpecWarnRisenWorshipper = "Show special warning when a Risen Worshipper appears"})

local timerEmbrace			= mod:NewBuffActiveTimer(30, 28732, nil, nil, nil, 6)
local timerEnrage			= mod:NewCDTimer(60, 28131, nil, nil, nil, 6)
local timerPoisonVolleyCD	= mod:NewCDTimer(14, 54098, nil, nil, nil, 5)
local timerRainOfFireCD		= mod:NewNextTimer(12, 9250587, nil, nil, nil, 3) -- Frostmourne custom, log 2026-10-06: every 12.0-12.1

mod.vb.enraged = false
local risenSeen = {}

-- Frostmourne logs (25-man 10-06/10-07/10-11/10-13, 10-man 10-08/10-12, 7 kills/wipes):
--  * Poison Bolt Volley keeps a fixed 14.05s rhythm from its first cast. Widow's Embrace silences her for 30s and only
--    skips the casts that fall into the silence - the next volley is the first tick of that rhythm after the silence
--    (matched all 6 embraces within 0.3s). The old code just showed a 10s bar 30s after the embrace.
--  * Frenzy: first one 74.6 (25) / 67.7 (10) when nothing interrupted it, and not health based (99%, 47%, 30%, 11%).
--    Embrace without frenzy up -> next frenzy 33.3 / 37.0 later (was 35). Embrace that removed a frenzy -> next one
--    76.6 later (and none for 69s in another pull; was 60).
--  * Widow's Embrace is also detected from the emote "is affected by Widow's Embrace" (25-man aura ID not confirmed).
local VOLLEY_CD = 14.05
local lastVolley
-- Frenzy schedule (server script, confirmed against the logs): first 60-80 after the pull, then 60-80 after each Frenzy.
-- Embrace that removes a Frenzy: next one 60-80 later. Embrace without Frenzy: next one after 30-40 or the remaining
-- timer, whichever is later. The bar shows the earliest possible time.
local frenzyAt -- GetTime() of the earliest next Frenzy

local function StartFrenzyTimer(sec)
	frenzyAt = GetTime() + sec
	timerEnrage:Stop()
	timerEnrage:Start(sec)
	warnEnrageSoon:Cancel()
	warnEnrageSoon:Schedule(sec - 5)
end

function mod:OnCombatStart(delay)
	table.wipe(risenSeen)
	-- Frostmourne raid reports as heroic25; logs 2026-10-06: first Frenzy at 74.1 and 74.6 (two pulls)
	lastVolley = nil
	StartFrenzyTimer(60 - delay)
	timerPoisonVolleyCD:Start(12.6-delay) -- REVIEW! variance? (25man Lordaeron 2022/10/16) - 12.6
	-- no Rain of Fire bar on pull: the first cast came at 8.6, 15.5 and 18.0 in three pulls
	self.vb.enraged = false
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpellID(28798, 54100) then -- Frenzy
		self.vb.enraged = true
		StartFrenzyTimer(60) -- next Frenzy 60-80 later
		--if self:IsTanking("player", nil, nil, true, args.destGUID) then -- Whitemane PTR (boss1 doesn't work currently, changed to GUID-based)
		if self:IsTanking("player", "boss1", nil, true) then -- seems to be fixed now
			specWarnEnrage:Show()
			specWarnEnrage:Play("defensive")
		else
			warnEnrageNow:Show()
		end
	elseif args:IsSpellID(28732, 54097)	and args:GetDestCreatureID() == 15953 and self:AntiSpam(5, 2) then	-- Widow's Embrace
		self:Embrace()
	elseif args:IsSpellID(28794, 54099, 9250587, 9250586) and args:IsPlayer() then
		specWarnGTFO:Show(args.spellName)
		specWarnGTFO:Play("watchfeet")
	end
end

function mod:Embrace()
	local isFrenzied = self.vb.enraged
	warnEmbraceExpire:Cancel()
	warnEmbraceExpired:Cancel()
	warnEnrageSoon:Cancel()
	timerPoisonVolleyCD:Cancel()
	if lastVolley then -- next volley = first tick of her 14.05s rhythm after the 30s silence
		local now = GetTime()
		local n = math.ceil((now + 30 - lastVolley) / VOLLEY_CD)
		timerPoisonVolleyCD:Start(lastVolley + n * VOLLEY_CD - now)
	end
	if isFrenzied then
		StartFrenzyTimer(60)
	else
		local remaining = frenzyAt and (frenzyAt - GetTime()) or 0
		StartFrenzyTimer(math.max(30, remaining))
	end
	timerEmbrace:Start()
	warnEmbraceActive:Show()
	warnEmbraceExpire:Schedule(25)
	warnEmbraceExpired:Schedule(30)
	self.vb.enraged = false
end

function mod:CHAT_MSG_RAID_BOSS_EMOTE(msg)
	if msg and msg:find("Widow's Embrace", 1, true) and self:AntiSpam(5, 2) then
		self:Embrace()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(28796, 54098, 9250585, 9250584) then -- 9250584: 10-man -- Poison Bolt Volley (9250585: Frostmourne custom)
		lastVolley = GetTime()
		timerPoisonVolleyCD:Start()
	elseif args:IsSpellID(9250587, 9250586) then -- Rain of Fire (Frostmourne custom; 9250586: 10-man)
		timerRainOfFireCD:Start()
	elseif args:IsSpellID(9250687, 9250686) then -- Vengeful Blight: only Risen Worshippers cast it (9250686: 10-man)
		if args.sourceGUID and not risenSeen[args.sourceGUID] then
			risenSeen[args.sourceGUID] = true
			specWarnRisen:Show()
			specWarnRisen:Play("killmob")
		end
	end
end

function mod:UNIT_DIED(args)
	local cid = self:GetCIDFromGUID(args.destGUID)
	if cid == 15953 then
		warnEnrageSoon:Cancel()
		warnEmbraceExpire:Cancel()
		warnEmbraceExpired:Cancel()
		timerPoisonVolleyCD:Cancel()
		timerRainOfFireCD:Cancel()
	end
end
