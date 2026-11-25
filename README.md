# Heirloom

Heirloom is a will for gno.land. You leave your GNOT and GRC20 tokens to the people you choose, and you can name a successor who takes over your admin rights in other realms. Until you go silent for the period you set, everything stays yours: you can deposit, withdraw, change heirs or revoke the will at any time.

Built for the Gnome Tavern hackathon. The repository also contains **The Keeper's Board**, a small demo realm whose admin passes to a successor through Heirloom.

## On the Onyx testnet

This version lives at the `/v1` package paths:

- Heirloom: https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1
- The Keeper's Board: https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/keepersboard/v1

Packages on gno.land cannot be changed once added. The paths without `/v1` hold an earlier version, without the objection period and without `Hide`; do not build on them.

## Why

On a chain, a lost key or a death is permanent. Funds sit untouched forever, and a realm whose admin is gone can never be updated again. Heirloom gives both a way out that needs no trusted third party: if the owner shows no sign of life for long enough, anyone can ask to release the will. If the owner still does not respond within 7 days, the heirs are paid and the admin rights move to the successor.

## How it works

1. **Make a will.** List heirs as `address:percent` pairs that add up to 100 (at most 10 heirs), choose a silence period from 1 to 3650 days, and optionally name a successor. You can have one unreleased will at a time.
2. **Fill it.** Deposit GNOT with the call, or deposit any GRC20 token registered in `grc20reg` after approving Heirloom as a spender. A will holds at most 10 different assets.
3. **Stay alive.** Every successful call you sign to Heirloom restarts the clock: `Ping`, a deposit, a change of heirs. So does using any realm that calls `heirloom.Touch`, such as The Keeper's Board. Transactions signed with a session key do not count, and a session key cannot create or change a will.
4. **Ask to release.** Once the silence period has passed, anyone but the owner can call `Release`. This only asks for the release: nothing is frozen or paid yet.
5. **Object.** The owner then has 7 days to object. Any sign of life, as in step 3, cancels the request, and the silence period starts again. Nothing happens by itself when the 7 days end: until someone calls `Release` again, a sign of life still cancels the request.
6. **Release.** When the 7 days have passed without a sign of life, the next `Release` releases the will. It is frozen as it stands: from then on nobody can deposit, withdraw or change it.
7. **Pay out.** Anyone can call `Claim(id, heir, asset)` to send an heir's share of one asset to that heir, so an heir that is a realm, or that cannot pay the fees, can still be paid. Shares are rounded down and the first heir gets the remainder, so payouts add up exactly to what the will held. A `Claim` after the 7 days also releases the will.
8. **Hand over admin rights.** Releasing a will hands the owner's admin rights to the successor, once and for good: nobody can undo it, not even the owner or the successor. If a later will of the same owner is released, it only leaves assets.

### Admin rights and `Holder`

`heirloom.Holder(addr)` returns who holds the admin rights of `addr`: `addr` itself until a released will of `addr` hands them on, then whoever holds the rights of that successor. Handovers chain: if your successor's own will is released later, your rights follow theirs. A handover that would loop back to the owner is refused, and the owner keeps the rights.

Heirloom does not change other realms by itself. A realm opts in by checking `Holder` instead of a fixed address:

```go
import "gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1"

var admin = address("g1...")

func AdminOnly(cur realm) {
	if !cur.IsCurrent() || cur.Previous().Address() != heirloom.Holder(admin) {
		panic("admin only")
	}
	heirloom.Touch(cross(cur))
}
```

`Touch` vouches only for the account that signed the transaction, so no realm can keep someone else's will from being released.

## Using it

The realm page in gnoweb has forms for every action: make a will on the home page, manage it on `:will/<id>`, and see your wills and the wills that name you on `:u/<address>`.

With gnokey:

```sh
PKG=gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1

# a will with two heirs, 180 days of silence and a successor
gnokey maketx call -pkgpath $PKG -func CreateWill \
  -args "g1heir...:70, g1other...:30" -args "180" -args "g1successor..." \
  -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid <chain> -remote <rpc> mykey

# put 5 GNOT into will 1
gnokey maketx call -pkgpath $PKG -func Deposit -args 1 -send 5000000ugnot ...

# after the silence period, anyone but the owner asks to release will 1; prints ("requested" string)
gnokey maketx call -pkgpath $PKG -func Release -args 1 ...

# 7 days later, if the owner did not object: release it, prints ("released" string), and pay an heir
gnokey maketx call -pkgpath $PKG -func Release -args 1 ...
gnokey maketx call -pkgpath $PKG -func Claim -args 1 -args "g1heir..." -args ugnot ...
```

## API

| Function | Who can call it | What it does |
| :--- | :--- | :--- |
| `CreateWill(heirs, silence, successor) int` | anyone, master key | Makes your will. |
| `SetHeirs(id, heirs)` | owner | Replaces the heirs. |
| `SetSuccessor(id, successor)` | owner | Sets or clears the successor. |
| `SetSilence(id, silence)` | owner | Changes the silence period. |
| `Ping(id)` | owner | Restarts the silence period and cancels a release request. |
| `Deposit(id)` | owner, direct call | Adds the GNOT sent with the call. |
| `DepositToken(id, token, amount)` | owner | Pulls an approved GRC20 amount into the will. |
| `Withdraw(id, asset, amount)` | owner | Sends an asset back to the owner. |
| `Revoke(id)` | owner | Returns everything and deletes the will. |
| `Release(id) string` | anyone but the owner | Asks to release a will whose silence period has passed; 7 days later, releases it. Returns `requested` or `released`. |
| `Claim(id, heir, asset)` | anyone, except the owner before release | Pays one heir's share of one asset, releasing the will first if its 7 days have passed. |
| `Hide(id)` | an heir or successor | Takes the will off your `:u/<address>` page; you can still be paid. |
| `Unhide(id)` | an heir or successor | Puts a hidden will back on your page. |
| `Touch()` | any realm | Sign of life for the transaction signer. |
| `Holder(addr) address` | read | Who holds the admin rights of `addr`. |
| `ActiveWill(owner) (id, ok)` | read | The owner's unreleased will. |
| `WillInfo(id) (owner, status, releaseAt, ok)` | read | Status: `active`, `due`, `requested` or `released`. |
| `WillURL(id) string`, `UserURL(addr) string` | read | gnoweb paths of a will's page and of an address's page, for links from other realms. |

Owner calls need the master key and are refused once the will is released. Amounts are in the asset's smallest unit (1 GNOT = 1000000 ugnot).

## The Keeper's Board

`demo/keepersboard` is a notice board whose keeper is `heirloom.Holder(founder)`, where the founder is the address in the board's package path, `gno.land/r/<address>/keepersboard/v1`; the board refuses to deploy under a path that does not start with an address. Anyone can post a note; the keeper pins one note and removes any. Every post, pin and removal calls `heirloom.Touch`, which counts unless the transaction was signed with a session key. When the founder's will is released, the board passes to the founder's successor with no change to the board's code, and its page says so.

## Design notes

- **Who is calling.** Every entry point checks `cur.IsCurrent()` and takes the caller from `cur.Previous()`, the realm or account that called it directly. Owner actions compare the owner with that caller, so a realm that the owner happens to call cannot act as the owner. `Release` and `Claim` refuse the owner both as that caller and as the signer of the transaction, so a will made by a realm cannot be released by that realm's own code.
- **Signs of life follow the signer.** `Touch`, `Release`, `Claim`, `Hide` and `Unhide` credit the account that signed the transaction (`OriginCaller`), even when the call comes through another realm, and `RequestedBy` records that signer. That can only extend the signer's own will; it never grants owner rights.
- **Coins.** GNOT is accepted only on a direct call (`IsUserCall`), so a `maketx run` script or another realm cannot reuse the coins attached to a transaction. Every other function refuses coins sent with a direct call.
- **Objection period.** Asking to release a will and releasing it are two calls, 7 days apart. A successor who stands to gain the owner's admin rights cannot take them in the first block after the silence period ends: the owner gets a week, and a public `ReleaseRequested` event, to answer.
- **Admin succession** is stored as a union-find: addresses whose rights end with the same holder share a group, so `Holder` answers in a few steps however long the chain of handovers grows, and a loop is detected by comparing two groups.
- **Why `chain/runtime/unsafe` is imported.** `OriginSend` is the only way to read the GNOT attached to a call, and it is read only behind `IsUserCall`. `OriginCaller` is used for signs of life and to keep the signing owner from releasing their own will, as above.
- **A released will is frozen.** Its holdings stay as they were at release and each heir's share is computed from them; a claim marks the heir as paid instead of rewriting the holdings.

## Known limitations

- Tokens of all wills sit at the realm's single address. If a token's issuer can take or burn tokens from that address, the realm holds less of that token than its wills add up to. Withdrawals and claims of that token then succeed first come, first served until the realm runs short, and the later ones fail; other assets are not affected, and sending the missing units back to the realm lets the remaining calls succeed.
- Coins or tokens sent to the realm's address directly, rather than with `Deposit` or `DepositToken`, are not added to any will and cannot be recovered. The will page warns about this next to the address.
- Admin rights pass only in realms that check `Holder`. Realms built on `ownable` or a fixed admin address are not affected.
- Only calls the owner signs to Heirloom or to realms that call `Touch` count as signs of life. An owner who stays active on the chain through bank sends, other realms or a session key, but does not touch Heirloom for the silence period and the 7 days after a request, loses the admin rights for good.
- On a network that restricts GNOT transfers (`ugnot` in the bank's `restricted_denoms`), an account that is allowed to transfer can still deposit, but nobody can withdraw or claim GNOT until the restriction is lifted. `Revoke` of a will holding GNOT fails as well. These calls fail as a whole, so nothing is lost, and the shares stay unclaimed. `Release` moves no coins, so it still works: the will is released and the admin rights pass on, while the GNOT waits until transfers are allowed again. Onyx and mainnet have no restricted denoms as of November 2026.
- Storage deposits are paid by whoever signs the call that stores data. In `heirloom_audit.txtar`, with 2 heirs, a successor, GNOT and one token, creating the will stores 14.3 KB, a deposit about 1 KB, asking for the release 0.2 KB, releasing 4.6 KB, and each claim 1 to 4 KB; the most is the first payout of a token to a new holder, which also opens that holder's balance in the token realm. At 100 ugnot per byte, as on Onyx and in the test node, 14.3 KB costs 1.43 GNOT. Freed bytes are refunded to the caller of that transaction. The owner's deposit is refunded on `Revoke`, not after release.
- The 10-asset limit is tested on the will's own bookkeeping, not with 11 real tokens.
- Anyone can name any address as an heir or successor without its consent. The address can take such a will off its `:u/<address>` page with the `hide` link there, and only the address itself can put it back, with `Unhide`; it still stays an heir or successor.

## Tests

In a gno checkout, copy the realm files to `examples/gno.land/r/<namespace>/heirloom/v1` and `demo/keepersboard` to `examples/gno.land/r/<namespace>/keepersboard/v1`, with `<namespace>` matching the module paths in `gnomod.toml`. Then, from `examples`:

```sh
gno test ./gno.land/r/<namespace>/heirloom/v1/
gno test ./gno.land/r/<namespace>/keepersboard/v1/
```

Heirloom has 43 tests and The Keeper's Board has 4. They cover the release request, the objection period and the signs of life that cancel it, payout, the exact moments a release can be asked for and completed, rounding and the largest amounts, admin succession through long chains and loops, a stranger trying to block a handover, calls made through other realms, deposit guards, hiding a will from a page and putting it back, a realm that cannot release its own will, a released will keeping its holdings, and the rendered pages. `gno fmt` and `gno lint` are clean. The whole flow, from a pinned note to the board passing to the successor, was also run on a local `gnodev` node with real transactions.

Four integration tests in [`integration/`](integration) run Heirloom on a real in-memory node with real transactions (gno v1.8.0, `gno.land/pkg/integration`). A day is patched down to 30 seconds, and the objection period to one such day, so that a will can be released during the test.

- `heirloom_audit.txtar`: coins sent through `maketx run`, to a function that takes none, or through another realm are refused; another realm cannot withdraw or revoke for the owner; GRC20 deposits; a release request with no payout and no handover during the objection period; release, payout of both assets to two heirs, and the realm's own GNOT and token balances back at zero.
- `heirloom_session.txtar`: a session key cannot ping, change or revoke a will, directly or through `maketx run`, and its `Touch` cancels no release request, while a `Ping` signed with the master key does.
- `heirloom_multimsg.txtar`: in a transaction with several messages, each message has its own coins: a `Deposit` without coins next to a paid one fails the whole transaction, and two paid deposits add up exactly.
- `heirloom_locked.txtar`: with GNOT transfers restricted, a restricted account cannot deposit; a withdrawal or revoke fails and the will keeps its GNOT; the will can still be released, but the GNOT claim fails and stays open.

Copy them to `gno.land/pkg/integration/testdata/` in a gno checkout that also holds the realm under `examples/`, then run:

```sh
go test ./gno.land/pkg/integration/ -run 'TestTestdata/heirloom_'
```

They wait with `exec sleep`, so they need a `sleep` command on the `PATH`.

## License

MIT, see [LICENSE](LICENSE).
