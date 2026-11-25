package heirloom

import (
	"chain"
	"chain/banker"
	"math"
	"strconv"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/tests/vm/test20"
)

const test20Key = "gno.land/r/tests/vm/test20.TST"

var (
	owner    = testutils.TestAddress("owner")
	anna     = testutils.TestAddress("anna")
	boris    = testutils.TestAddress("boris")
	stranger = testutils.TestAddress("stranger")
)

func reset() {
	state = newStore()
}

func withSend(ugnot int64) {
	if ugnot == 0 {
		testing.SetOriginSend(nil)
		return
	}
	coins := chain.Coins{{"ugnot", ugnot}}
	testing.SetOriginSend(coins)
	testing.IssueCoins(selfAddr, coins)
}

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoin(addr, "ugnot")
}

func silenceJustOver(id int) {
	w := getWill(id)
	w.LastSeen = time.Now().Add(-w.Silence - time.Minute)
}

func silenceOver(id int) {
	w := getWill(id)
	w.LastSeen = time.Now().Add(-w.Silence - ObjectionPeriod - 2*time.Minute)
	w.RequestedAt, w.RequestedBy = time.Now().Add(-ObjectionPeriod-time.Minute), stranger
}

func heirs(pairs ...string) string {
	return strings.Join(pairs, ", ")
}

func TestReleaseAndClaim(cur realm, t *testing.T) {
	reset()
	start := balance(selfAddr)

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":70", boris.String()+":30"), "180d", anna)
	withSend(1_000_001)
	Deposit(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(stranger))
	withSend(0)
	uassert.AbortsContains(t, cur, "the will can be released from", func() {
		Release(cross(cur), id)
	})
	uassert.Equal(t, owner, Holder(owner))

	silenceOver(id)
	Release(cross(cur), id)
	uassert.Equal(t, anna, Holder(owner))
	uassert.AbortsWithMessage(t, cur, "the will is already released", func() {
		Release(cross(cur), id)
	})
	uassert.AbortsWithMessage(t, cur, stranger.String()+" is not an heir of this will", func() {
		Claim(cross(cur), id, stranger, gnot)
	})

	annaBefore, borisBefore, strangerBefore := balance(anna), balance(boris), balance(stranger)
	Claim(cross(cur), id, boris, gnot)
	uassert.Equal(t, strangerBefore, balance(stranger))
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	Claim(cross(cur), id, anna, gnot)
	uassert.AbortsWithMessage(t, cur, anna.String()+" has already been paid their share of ugnot", func() {
		Claim(cross(cur), id, anna, gnot)
	})
	uassert.AbortsWithMessage(t, cur, "the will held no "+test20Key+" when it was released", func() {
		Claim(cross(cur), id, anna, test20Key)
	})

	uassert.Equal(t, annaBefore+700_001, balance(anna))
	uassert.Equal(t, borisBefore+300_000, balance(boris))
	uassert.Equal(t, start, balance(selfAddr))
	uassert.Equal(t, int64(0), state.totalGNOT)
}

func TestOwnerCanStartAgainAfterRelease(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	first := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	silenceOver(first)

	testing.SetRealm(testing.NewUserRealm(stranger))
	withSend(0)
	Release(cross(cur), first)

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	uassert.AbortsWithMessage(t, cur, "will 1 is already released", func() {
		Ping(cross(cur), first)
	})
	second := CreateWill(cross(cur), boris.String()+":100", "30d", "")
	uassert.Equal(t, 2, second)
	uassert.Equal(t, anna, Holder(owner))
	active, ok := ActiveWill(owner)
	uassert.True(t, ok)
	uassert.Equal(t, second, active)
}

func TestAdminRightsPassOnlyOnce(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	first := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	silenceOver(first)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), first)
	testing.SetRealm(testing.NewUserRealm(owner))

	second := CreateWill(cross(cur), boris.String()+":100", "1d", "")
	uassert.AbortsWithMessage(t, cur, "will 1 already handed your admin rights to "+anna.String(), func() {
		SetSuccessor(cross(cur), second, boris)
	})
	SetHeirs(cross(cur), second, heirs(boris.String()+":60", stranger.String()+":40"))
	uassert.Equal(t, address(""), getWill(second).Successor)
	page := Render("will/2")
	uassert.True(t, strings.Contains(page, "Releasing [will 1]("))
	uassert.True(t, strings.Contains(page, "handed them to ["+shortAddr(anna)))
	uassert.False(t, strings.Contains(page, `exec="SetSuccessor"`))
	silenceOver(second)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), second)

	uassert.Equal(t, anna, Holder(owner))
	outcome, _ := adminOutcomeOf(getWill(second))
	uassert.True(t, outcome == adminHandedOverByAnother)
}

func TestHandoverNamesTheWillThatPassedIt(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), owner.String()+":100", "1d", owner)
	silenceOver(annasWill)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), annasWill)

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	looping := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	silenceOver(looping)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), looping)
	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.True(t, strings.Contains(Render("will/2"), "already passed to the owner"))

	passing := CreateWill(cross(cur), boris.String()+":100", "1d", boris)
	silenceOver(passing)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), passing)

	uassert.Equal(t, boris, Holder(owner))
	uassert.True(t, strings.Contains(Render("will/2"), "Releasing [will 3]("))
	uassert.True(t, strings.Contains(Render("will/2"), "handed them to ["+shortAddr(boris)+"]("))
}

func TestSuccessionNeverLoops(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	ownersWill := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), owner.String()+":100", "1d", owner)

	silenceOver(ownersWill)
	silenceOver(annasWill)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), ownersWill)
	Release(cross(cur), annasWill)

	uassert.Equal(t, anna, Holder(owner))
	uassert.Equal(t, anna, Holder(anna))
	uassert.Equal(t, anna, Holder(address(strings.ToUpper(owner.String()))))
	id, ok := ActiveWill(address(strings.ToUpper(owner.String())))
	uassert.False(t, ok)
	uassert.Equal(t, 0, id)
}

func TestOwnerActivityRestartsTheClock(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	silenceOver(id)
	Ping(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	uassert.AbortsContains(t, cur, "the will can be released from", func() {
		Claim(cross(cur), id, anna, gnot)
	})
}

func TestTouchVouchesOnlyForSigner(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	silenceOver(id)
	w := getWill(id)
	stale := w.LastSeen

	app := testing.NewCodeRealm("gno.land/r/someone/app")
	withSend(500)
	testing.SetOriginCaller(stranger)
	testing.SetRealm(app)
	Touch(cross(cur))
	uassert.True(t, w.LastSeen.Equal(stale))

	testing.SetOriginCaller(owner)
	testing.SetRealm(app)
	Touch(cross(cur))
	uassert.False(t, w.isDue())
}

func TestSuccessionFollowsTheLine(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	ownersWill := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), boris.String()+":100", "1d", boris)

	silenceOver(ownersWill)
	silenceOver(annasWill)
	testing.SetRealm(testing.NewUserRealm(stranger))
	withSend(0)
	Release(cross(cur), ownersWill)
	uassert.Equal(t, anna, Holder(owner))
	Release(cross(cur), annasWill)
	uassert.Equal(t, boris, Holder(owner))
	uassert.True(t, strings.Contains(Render("u/"+owner.String()), "now belong to ["+shortAddr(boris)))
}

func TestClaimsAreIsolatedPerAsset(cur realm, t *testing.T) {
	reset()

	ownerBefore, annaTokens, borisTokens := test20.Token.BalanceOf(owner), test20.Token.BalanceOf(anna), test20.Token.BalanceOf(boris)
	test20.PrivateLedger.Mint(owner, 10_000)
	test20.PrivateLedger.Approve(owner, selfAddr, 10_000)

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":50", boris.String()+":50"), "1d", anna)
	DepositToken(cross(cur), id, test20Key, 9_001)
	Withdraw(cross(cur), id, test20Key, 1)
	withSend(2_000_000)
	Deposit(cross(cur), id)
	uassert.Equal(t, "0.9 TST", describe(test20Key).amount(getWill(id).balance(test20Key)))
	uassert.True(t, strings.Contains(Render("will/1"), "(`"+test20Key+"`)"))

	silenceOver(id)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	Claim(cross(cur), id, anna, test20Key)
	annaBefore := balance(anna)
	Claim(cross(cur), id, anna, gnot)
	testing.SetRealm(testing.NewUserRealm(boris))
	withSend(0)
	Claim(cross(cur), id, boris, test20Key)

	uassert.Equal(t, annaTokens+4_500, test20.Token.BalanceOf(anna))
	uassert.Equal(t, borisTokens+4_500, test20.Token.BalanceOf(boris))
	uassert.Equal(t, ownerBefore+1_000, test20.Token.BalanceOf(owner))
	uassert.Equal(t, int64(0), test20.Token.BalanceOf(selfAddr))
	uassert.Equal(t, annaBefore+1_000_000, balance(anna))
	uassert.Equal(t, int64(1_000_000), getWill(id).balance(gnot))
}

func TestRevokeReturnsEverything(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	withSend(2_000_000)
	Deposit(cross(cur), id)

	test20.PrivateLedger.Mint(owner, 500)
	test20.PrivateLedger.Approve(owner, selfAddr, 500)
	withSend(0)
	DepositToken(cross(cur), id, test20Key, 500)
	tokensBefore := test20.Token.BalanceOf(owner)

	before := balance(owner)
	Revoke(cross(cur), id)
	uassert.Equal(t, before+2_000_000, balance(owner))
	uassert.Equal(t, tokensBefore+500, test20.Token.BalanceOf(owner))
	uassert.True(t, getWill(id) == nil)
	_, _, _, found := WillInfo(id)
	uassert.False(t, found)
	uassert.True(t, strings.Contains(Render("u/"+owner.String()), "## Wills made\n\nNone."))
	_, ok := ActiveWill(owner)
	uassert.False(t, ok)
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as heir\n\nNone."))
}

func TestValidation(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	cases := map[string]string{
		anna.String() + ":60":                                            "heir percentages add up to 60, not 100",
		heirs(anna.String()+":50", anna.String()+":50"):                  "heir listed twice",
		heirs(strings.ToUpper(anna.String())+":50", anna.String()+":50"): "heir listed twice",
		strings.ToUpper(owner.String()) + ":100":                         "you cannot be your own heir",
		selfAddr.String() + ":100":                                       "this realm cannot be an heir",
		"nobody:100":                                                     "invalid heir address",
		anna.String():                                                    "heirs must look like",
		heirs(anna.String()+":0", boris.String()+":100"):                 "each heir's percent must be between 1 and 100",
	}
	var many []string
	for i := 0; i < MaxHeirs+1; i++ {
		many = append(many, testutils.TestAddress("heir"+string(rune('a'+i))).String()+":1")
	}
	cases[heirs(many...)] = "a will can have at most 10 heirs"
	for list, msg := range cases {
		uassert.AbortsContains(t, cur, msg, func() { CreateWill(cross(cur), list, "30d", "") }, list)
	}
	for _, silence := range []string{"", "0", "0d", "12h", "3651d", "640512d", "-213503d", "xd"} {
		uassert.AbortsContains(t, cur, "silence must be", func() {
			CreateWill(cross(cur), anna.String()+":100", silence, anna)
		}, silence)
	}

	id := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	uassert.AbortsWithMessage(t, cur, "you already have an unreleased will", func() {
		CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	})
	successors := map[address]string{
		owner:    "you cannot be your own successor",
		selfAddr: "this realm cannot be a successor",
		"nobody": "invalid successor address",
	}
	for successor, msg := range successors {
		uassert.AbortsContains(t, cur, msg, func() { SetSuccessor(cross(cur), id, successor) })
	}
	SetSuccessor(cross(cur), id, address(strings.ToUpper(boris.String())))
	uassert.Equal(t, boris, getWill(id).Successor)
	withSend(1)
	uassert.AbortsWithMessage(t, cur, "this function does not accept coins", func() {
		Ping(cross(cur), id)
	})

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/shop"))
	withSend(1_000_000)
	uassert.AbortsWithMessage(t, cur, "you own this will: call Ping to show a sign of life", func() {
		Release(cross(cur), 1)
	})
	testing.SetOriginCaller(stranger)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/shop"))
	uassert.AbortsContains(t, cur, "the will can be released from", func() {
		Release(cross(cur), 1)
	})
}

func TestSuccessorIsIndependentOfHeirs(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	SetHeirs(cross(cur), id, boris.String()+":100")
	uassert.Equal(t, anna, getWill(id).Successor)
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as successor"))

	SetSuccessor(cross(cur), id, "")
	uassert.Equal(t, address(""), getWill(id).Successor)
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as successor\n\nNone."))
	uassert.True(t, strings.Contains(Render("will/1"), "No successor: the owner keeps them"))

	silenceOver(id)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), id)
	uassert.Equal(t, owner, Holder(owner))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as heir\n\nNone."))
	uassert.True(t, strings.Contains(Render("u/"+boris.String()), "100%"))
}

func TestRender(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":70", boris.String()+":30"), "180d", anna)

	uassert.True(t, strings.Contains(Render(""), "# Heirloom"))
	page := Render("will/1")
	uassert.True(t, strings.Contains(page, "data:image/svg+xml;base64,"))
	uassert.True(t, strings.Contains(page, "| active |"))
	uassert.True(t, strings.Contains(page, `value="180"`))

	uassert.False(t, strings.Contains(page, "exec=\"Withdraw\""))
	withSend(1_000_000)
	Deposit(cross(cur), id)
	uassert.True(t, strings.Contains(Render("will/1"), `<gno-select name="asset" value="ugnot" description="Asset" />`))

	silenceJustOver(id)
	due := Render("will/1")
	uassert.True(t, strings.Contains(due, "due: anyone but the owner can ask to release it"))
	uassert.True(t, strings.Contains(due, "[ask to release the will]("))
	uassert.True(t, strings.Contains(due, "The owner then has 7 days to object."))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "70%, due"))

	testing.SetRealm(testing.NewUserRealm(stranger))
	withSend(0)
	Release(cross(cur), id)
	requested := Render("will/1")
	uassert.True(t, strings.Contains(requested, "| requested by "))
	uassert.True(t, strings.Contains(requested, "released unless the owner shows a sign of life"))
	uassert.True(t, strings.Contains(requested, "| Can be released from |"))
	uassert.True(t, strings.Contains(requested, "7d to object"))
	uassert.False(t, strings.Contains(requested, "[release the will]("))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "70%, requested"))

	silenceOver(id)
	ripe := Render("will/1")
	uassert.True(t, strings.Contains(ripe, "[release the will]("))
	uassert.True(t, strings.Contains(ripe, "Then anyone can pay out each heir's share."))

	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	Claim(cross(cur), id, anna, gnot)
	released := Render("will/1")
	uassert.Equal(t, 1, strings.Count(released, "[pay out]("))
	uassert.True(t, strings.Contains(released, "heir="+boris.String()))
	uassert.True(t, strings.Contains(released, "| paid |"))
	uassert.True(t, strings.Contains(released, "| Released on |"))
	uassert.False(t, strings.Contains(released, "Release can be asked for from"))

	testing.SetRealm(testing.NewUserRealm(boris))
	withSend(0)
	empty := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	silenceOver(empty)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), empty)
	uassert.True(t, strings.Contains(Render("will/2"), "Nothing to claim."))

	uassert.True(t, strings.Contains(Render("will/3"), "No such will"))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()+"/461168601842738791"), "Page not found"))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()+"/2"), "Page not found"))
	uassert.True(t, strings.Contains(Render("u/nope"), "Invalid address"))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()+"/0"), "Page not found"))
	uassert.True(t, strings.Contains(Render("x/y"), "Page not found"))
}

func TestHeirPagePaginates(cur realm, t *testing.T) {
	reset()

	for i := 0; i < listPageLen+3; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("spammer" + string(rune('a'+i)))))
		withSend(0)
		CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	}
	first := Render("u/" + anna.String())
	uassert.Equal(t, listPageLen, strings.Count(first, "100%"))
	uassert.True(t, strings.Contains(first, "[More]("))
	uassert.Equal(t, 3, strings.Count(Render("u/"+anna.String()+"/2"), "100%"))
}

func TestOwnPagePaginates(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	for i := 0; i < listPageLen+2; i++ {
		id := CreateWill(cross(cur), anna.String()+":100", "1d", "")
		silenceOver(id)
		testing.SetRealm(testing.NewUserRealm(stranger))
		Release(cross(cur), id)
		testing.SetRealm(testing.NewUserRealm(owner))
	}
	first := Render("u/" + owner.String())
	uassert.Equal(t, listPageLen, strings.Count(first, ": released"))
	uassert.Equal(t, 1, strings.Count(first, "[More]("))
	second := Render("u/" + owner.String() + "/2")
	uassert.True(t, strings.Contains(second, "## Wills made"))
	uassert.Equal(t, 2, strings.Count(second, ": released"))
	uassert.False(t, strings.Contains(second, "[More]("))
}

func TestFormatting(t *testing.T) {
	at := time.Date(2030, 1, 2, 12, 0, 30, 0, time.UTC)
	uassert.Equal(t, "2030-01-02 12:01 UTC", formatTimeFrom(at))
	uassert.Equal(t, "2030-01-02 12:00 UTC", formatTimeFrom(at.Truncate(time.Minute)))
	uassert.Equal(t, "<1m", formatDuration(59*time.Second))
	uassert.Equal(t, "180d", formatDuration(180*day))
	uassert.Equal(t, "2h 5m", formatDuration(125*time.Minute))
	uassert.Equal(t, "3650d", formatDuration(MaxSilence))
	uassert.Equal(t, "1.5 GNOT", describe(gnot).amount(1_500_000))
	uassert.Equal(t, "0.000001 GNOT", describe(gnot).amount(1))
}

func TestLongLinesFollowEveryHandover(cur realm, t *testing.T) {
	reset()

	line := make([]address, 40)
	for i := range line {
		line[i] = testutils.TestAddress("link" + string(rune('a'+i)))
	}
	last := line[len(line)-1]
	var steps [][2]address
	for i := 0; i < 20; i++ {
		steps = append(steps, [2]address{line[i], line[i+1]})
	}
	for i := len(line) - 2; i >= 20; i-- {
		steps = append(steps, [2]address{line[i], line[i+1]})
	}
	steps = append(steps, [2]address{owner, line[0]}, [2]address{last, owner})

	var looping int
	for _, step := range steps {
		testing.SetRealm(testing.NewUserRealm(step[0]))
		withSend(0)
		looping = CreateWill(cross(cur), step[1].String()+":100", "1d", step[1])
		silenceOver(looping)
		testing.SetRealm(testing.NewUserRealm(stranger))
		Release(cross(cur), looping)
	}

	uassert.Equal(t, last, Holder(line[0]))
	uassert.Equal(t, last, Holder(line[20]))
	uassert.Equal(t, last, Holder(owner))
	uassert.Equal(t, last, Holder(last))
	outcome, _ := adminOutcomeOf(getWill(looping))
	uassert.True(t, outcome == adminStaysWithOwner)
	uassert.True(t, strings.Contains(Render("will/"+strconv.Itoa(looping)), "already passed to the owner"))
}

func TestStrangersCannotBlockAHandover(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)

	for i := 0; i < 40; i++ {
		from := testutils.TestAddress("atk" + string(rune('a'+i)))
		to := owner
		if i < 39 {
			to = testutils.TestAddress("atk" + string(rune('a'+i+1)))
		}
		testing.SetRealm(testing.NewUserRealm(from))
		withSend(0)
		atk := CreateWill(cross(cur), to.String()+":100", "1d", to)
		silenceOver(atk)
		testing.SetRealm(testing.NewUserRealm(stranger))
		Release(cross(cur), atk)
	}

	silenceOver(id)
	Release(cross(cur), id)
	uassert.Equal(t, anna, Holder(owner))
}

func TestReleasingIsASignOfLife(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	ownersWill := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), boris.String()+":100", "1d", boris)
	silenceOver(ownersWill)
	silenceOver(annasWill)

	Release(cross(cur), ownersWill)
	uassert.True(t, getWill(annasWill).status() == statusActive)
}

func TestWillInfo(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1d", anna)

	who, status, releaseAt, ok := WillInfo(id)
	uassert.True(t, ok)
	uassert.Equal(t, owner, who)
	uassert.Equal(t, "active", status)
	uassert.True(t, releaseAt.Equal(getWill(id).releaseAt()))

	silenceJustOver(id)
	_, status, _, _ = WillInfo(id)
	uassert.Equal(t, "due", status)

	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), id)
	_, status, releaseAt, _ = WillInfo(id)
	uassert.Equal(t, "requested", status)
	uassert.True(t, releaseAt.Equal(getWill(id).objectionEnds()))

	_, _, _, ok = WillInfo(99)
	uassert.False(t, ok)
}

func TestSetSilence(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	SetSilence(cross(cur), id, " 7d ")
	uassert.True(t, getWill(id).Silence == 7*day)

	for _, bad := range []string{"0d", "3651", "7h", "-1d", ""} {
		uassert.AbortsContains(t, cur, "silence must be a number of days from 1 to 3650, e.g. 180", func() {
			SetSilence(cross(cur), id, bad)
		})
	}
	uassert.True(t, getWill(id).Silence == 7*day)

	testing.SetRealm(testing.NewUserRealm(anna))
	uassert.AbortsWithMessage(t, cur, "only the owner can change will 1", func() {
		SetSilence(cross(cur), id, "1d")
	})
}

func TestOnlyTheOwnerChangesAWill(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	mine := CreateWill(cross(cur), boris.String()+":100", "30d", boris)

	uassert.AbortsWithMessage(t, cur, "only the owner can change will 1", func() {
		Revoke(cross(cur), id)
	})
	uassert.AbortsWithMessage(t, cur, "only the owner can change will 1", func() {
		SetHeirs(cross(cur), id, stranger.String()+":100")
	})
	uassert.Equal(t, anna, getWill(id).Heirs[0].Addr)
	uassert.Equal(t, boris, getWill(mine).Heirs[0].Addr)
	uassert.True(t, strings.Contains(Render("will/1"), `name="id" value="1" readonly="true"`))
}

func TestDepositGuards(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "30d", anna)

	testing.SetOriginSend(chain.Coins{{"foo", 5}})
	uassert.AbortsWithMessage(t, cur, "attach the GNOT to deposit", func() {
		Deposit(cross(cur), id)
	})
	testing.SetOriginSend(chain.Coins{{"ugnot", 5}, {"foo", 5}})
	uassert.AbortsWithMessage(t, cur, "attach the GNOT to deposit", func() {
		Deposit(cross(cur), id)
	})

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/relay"))
	withSend(1_000_000)
	uassert.AbortsContains(t, cur, "coins must be sent with a direct call", func() {
		Deposit(cross(cur), id)
	})
	uassert.Equal(t, int64(0), getWill(id).balance(gnot))
}

func TestClaimIsASignOfLife(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	ownersWill := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	withSend(1_000_000)
	Deposit(cross(cur), ownersWill)
	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), boris.String()+":100", "1d", boris)
	silenceOver(ownersWill)
	silenceOver(annasWill)

	Claim(cross(cur), ownersWill, anna, gnot)
	uassert.True(t, getWill(annasWill).status() == statusActive)
}

func TestOwnerCannotReleaseOwnWill(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	silenceJustOver(id)
	uassert.AbortsWithMessage(t, cur, "you own this will: call Ping to show a sign of life", func() {
		Release(cross(cur), id)
	})
	uassert.True(t, getWill(id).status() == statusDue)
	uassert.True(t, strings.Contains(Render("will/1"), "Anyone but the owner: [ask to release the will]("))
}

func TestWithdrawGuards(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	withSend(10)
	Deposit(cross(cur), id)
	withSend(0)

	for _, amount := range []int64{0, -1} {
		uassert.AbortsWithMessage(t, cur, "amount must be positive", func() {
			Withdraw(cross(cur), id, gnot, amount)
		})
	}
	uassert.AbortsWithMessage(t, cur, "the will does not hold that much of ugnot", func() {
		Withdraw(cross(cur), id, gnot, 11)
	})

	testing.SetRealm(testing.NewUserRealm(anna))
	uassert.AbortsWithMessage(t, cur, "only the owner can change will 1", func() {
		Withdraw(cross(cur), id, gnot, 1)
	})

	silenceOver(id)
	Release(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.AbortsWithMessage(t, cur, "will 1 is already released", func() {
		Withdraw(cross(cur), id, gnot, 1)
	})

	testing.SetRealm(testing.NewUserRealm(anna))
	Claim(cross(cur), id, anna, gnot)
	page := Render("will/1")
	uassert.True(t, strings.Contains(page, "When this will was released, it handed them to ["+shortAddr(anna)))
	uassert.True(t, strings.Contains(page, "| paid |"))
	uassert.False(t, strings.Contains(page, "[pay out]("))
}

func TestZeroShareIsNothingToClaim(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":50", boris.String()+":50"), "1d", anna)
	withSend(1)
	Deposit(cross(cur), id)
	silenceOver(id)

	testing.SetRealm(testing.NewUserRealm(boris))
	withSend(0)
	uassert.AbortsWithMessage(t, cur, boris.String()+"'s share of ugnot rounds down to 0", func() {
		Claim(cross(cur), id, boris, gnot)
	})
	testing.SetRealm(testing.NewUserRealm(anna))
	Claim(cross(cur), id, anna, gnot)
	page := Render("will/1")
	uassert.True(t, strings.Contains(page, "| nothing to pay |"))
	uassert.False(t, strings.Contains(page, "[pay out]("))

	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.AbortsWithMessage(t, cur, "the will is already released", func() {
		Release(cross(cur), id)
	})
}

func TestPageNamesTheCurrentHolder(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	annasWill := CreateWill(cross(cur), boris.String()+":100", "1d", boris)
	silenceOver(annasWill)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), annasWill)

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	uassert.True(t, strings.Contains(Render("will/2"), "already passed to ["+shortAddr(boris)))

	silenceOver(id)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Release(cross(cur), id)
	uassert.Equal(t, boris, Holder(owner))
	uassert.True(t, strings.Contains(Render("will/2"), "They are now held by ["+shortAddr(boris)))
}

func TestAnyoneCanPayOutAnHeir(cur realm, t *testing.T) {
	reset()

	dao := testing.NewCodeRealm("gno.land/r/someone/dao").Address()
	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(dao.String()+":60", anna.String()+":40"), "1d", stranger)
	withSend(1_000)
	Deposit(cross(cur), id)
	silenceOver(id)
	withSend(0)
	uassert.AbortsWithMessage(t, cur, "you own this will: call Ping to show a sign of life", func() {
		Claim(cross(cur), id, dao, gnot)
	})

	daoBefore, strangerBefore := balance(dao), balance(stranger)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Claim(cross(cur), id, dao, gnot)
	uassert.Equal(t, daoBefore+600, balance(dao))
	uassert.Equal(t, strangerBefore, balance(stranger))
	uassert.Equal(t, stranger, Holder(owner))

	testing.SetRealm(testing.NewUserRealm(owner))
	annaBefore := balance(anna)
	Claim(cross(cur), id, anna, gnot)
	uassert.Equal(t, annaBefore+400, balance(anna))
	uassert.AbortsWithMessage(t, cur, "will 1 already handed your admin rights to "+stranger.String(), func() {
		CreateWill(cross(cur), anna.String()+":100", "1d", anna)
	})
}

func TestCallsThroughARealmCountForTheSigner(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1d", "")
	silenceOver(id)
	testing.SetRealm(testing.NewUserRealm(anna))
	annasWill := CreateWill(cross(cur), boris.String()+":100", "1d", "")
	silenceOver(annasWill)

	testing.SetOriginCaller(anna)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/keeper"))
	Release(cross(cur), id)
	uassert.True(t, getWill(annasWill).status() == statusActive)

	testing.SetOriginCaller(boris)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/keeper"))
	uassert.AbortsWithMessage(t, cur, "the will is already released", func() {
		Release(cross(cur), id)
	})
}

func TestReleaseOpensExactlyWhenTheWaitEnds(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1", anna)
	w := getWill(id)

	testing.SetRealm(testing.NewUserRealm(stranger))
	w.LastSeen = time.Now().Add(-w.Silence + time.Second)
	uassert.AbortsContains(t, cur, "the will can be released from", func() {
		Release(cross(cur), id)
	})
	w.LastSeen = time.Now().Add(-w.Silence)
	Release(cross(cur), id)
	uassert.True(t, w.status() == statusRequested)
	uassert.Equal(t, stranger, w.RequestedBy)
	uassert.AbortsContains(t, cur, "the owner can object until", func() {
		Release(cross(cur), id)
	})

	w.LastSeen = time.Now().Add(-w.Silence - ObjectionPeriod)
	w.RequestedAt = time.Now().Add(-ObjectionPeriod + time.Second)
	uassert.AbortsContains(t, cur, "the owner can object until", func() {
		Release(cross(cur), id)
	})
	w.RequestedAt = time.Now().Add(-ObjectionPeriod)
	Release(cross(cur), id)
	uassert.True(t, w.isReleased())
}

func TestAnySignOfLifeCancelsARequest(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1", anna)
	w := getWill(id)
	request := func() {
		silenceJustOver(id)
		testing.SetRealm(testing.NewUserRealm(stranger))
		testing.SetOriginCaller(stranger)
		withSend(0)
		Release(cross(cur), id)
		uassert.True(t, w.status() == statusRequested)
	}

	request()
	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(1_000_000)
	Deposit(cross(cur), id)
	uassert.True(t, w.status() == statusActive)
	uassert.True(t, w.RequestedAt.IsZero())
	uassert.Equal(t, int64(1_000_000), w.balance(gnot))

	request()
	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someone/app"))
	withSend(0)
	Touch(cross(cur))
	uassert.True(t, w.status() == statusActive)

	request()
	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	Ping(cross(cur), id)
	uassert.True(t, w.status() == statusActive)
	uassert.Equal(t, owner, Holder(owner))

	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.AbortsContains(t, cur, "the will can be released from", func() {
		Release(cross(cur), id)
	})
}

func TestClaimWaitsForTheRequestAndTheObjectionPeriod(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1", boris)
	withSend(1_000_000)
	Deposit(cross(cur), id)
	silenceJustOver(id)

	testing.SetRealm(testing.NewUserRealm(anna))
	withSend(0)
	uassert.AbortsContains(t, cur, "nobody has asked to release this will yet: call Release first", func() {
		Claim(cross(cur), id, anna, gnot)
	})
	Release(cross(cur), id)
	uassert.AbortsContains(t, cur, "the owner can object until", func() {
		Claim(cross(cur), id, anna, gnot)
	})
	uassert.Equal(t, owner, Holder(owner))

	silenceOver(id)
	before := balance(anna)
	Claim(cross(cur), id, anna, gnot)
	uassert.Equal(t, before+1_000_000, balance(anna))
	uassert.Equal(t, boris, Holder(owner))
	uassert.True(t, getWill(id).isReleased())
}

func TestSilenceBoundsAreAccepted(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "3650", anna)
	uassert.True(t, getWill(id).Silence == MaxSilence)
	SetSilence(cross(cur), id, " 1d ")
	uassert.True(t, getWill(id).Silence == MinSilence)
}

func TestSharesOfTheLargestAmountAddUp(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":70", boris.String()+":29", stranger.String()+":1"), "1", anna)
	w := getWill(id)
	w.snapshot.Set(gnot, int64(math.MaxInt64))

	var total int64
	for _, h := range w.Heirs {
		share := w.shareOf(h, gnot)
		uassert.True(t, share > 0)
		total += share
	}
	uassert.Equal(t, int64(math.MaxInt64), total)
	uassert.Equal(t, int64(math.MaxInt64)/100, w.shareOf(w.Heirs[2], gnot))
}

func TestHoldingsCannotOverflow(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	w := getWill(CreateWill(cross(cur), anna.String()+":100", "1", anna))
	w.add(gnot, math.MaxInt64)
	uassert.PanicsContains(t, cur, "the will cannot hold that much of ugnot", func() {
		w.add(gnot, 1)
	})
	uassert.Equal(t, int64(math.MaxInt64), w.balance(gnot))
}

func TestAWillHoldsAtMostTenAssets(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	w := getWill(CreateWill(cross(cur), anna.String()+":100", "1", anna))
	for i := 0; i < MaxAssets; i++ {
		w.add("gno.land/r/test/t"+strconv.Itoa(i)+".T", 1)
	}
	w.add("gno.land/r/test/t0.T", 1)
	uassert.Equal(t, int64(2), w.balance("gno.land/r/test/t0.T"))
	uassert.PanicsContains(t, cur, "a will can hold at most 10 different assets", func() {
		w.add(gnot, 1)
	})
	w.take("gno.land/r/test/t1.T", 1)
	w.add(gnot, 1)
	uassert.Equal(t, MaxAssets, len(w.assets()))
}

func TestOwnerCanStillRevokeADueWill(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), anna.String()+":100", "1", anna)
	withSend(1_000_000)
	Deposit(cross(cur), id)
	silenceOver(id)
	uassert.True(t, getWill(id).isDue())

	withSend(0)
	before := balance(owner)
	Revoke(cross(cur), id)
	uassert.Equal(t, before+1_000_000, balance(owner))

	testing.SetRealm(testing.NewUserRealm(anna))
	uassert.AbortsContains(t, cur, "no such will", func() {
		Claim(cross(cur), id, anna, gnot)
	})
}

func TestHeirsAndSuccessorsCanHideAWill(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(owner))
	withSend(0)
	id := CreateWill(cross(cur), heirs(anna.String()+":60", boris.String()+":40"), "1", anna)
	withSend(1_000_000)
	Deposit(cross(cur), id)
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "with `Hide`"))

	testing.SetRealm(testing.NewUserRealm(stranger))
	withSend(0)
	uassert.AbortsWithMessage(t, cur, "will 1 does not name you as an heir or successor", func() {
		Hide(cross(cur), id)
	})

	testing.SetRealm(testing.NewUserRealm(anna))
	Hide(cross(cur), id)
	page := Render("u/" + anna.String())
	uassert.True(t, strings.Contains(page, "## Named as heir\n\nNone."))
	uassert.True(t, strings.Contains(page, "## Named as successor\n\nNone."))
	uassert.True(t, strings.Contains(Render("u/"+boris.String()), "60%") == false)
	uassert.True(t, strings.Contains(Render("u/"+boris.String()), "40%, active"))

	testing.SetRealm(testing.NewUserRealm(owner))
	SetHeirs(cross(cur), id, heirs(anna.String()+":50", boris.String()+":50"))
	SetSuccessor(cross(cur), id, anna)
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as heir\n\nNone."))
	uassert.True(t, strings.Contains(Render("u/"+anna.String()), "## Named as successor\n\nNone."))

	silenceOver(id)
	testing.SetRealm(testing.NewUserRealm(anna))
	before := balance(anna)
	Claim(cross(cur), id, anna, gnot)
	uassert.Equal(t, before+500_000, balance(anna))
	uassert.Equal(t, anna, Holder(owner))
}
