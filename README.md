# Heirloom

Heirloom is a will for gno.land. You leave your GNOT and GRC20 tokens to the people you choose and can name a successor for your admin rights in other realms. Until you go silent for the period you set, everything stays yours.

Built for the Gnome Tavern hackathon. The repository also contains **The Keeper's Board**, a small demo realm whose admin passes to a successor through Heirloom.

## Deployment

Live on the Onyx testnet:

- Heirloom: [gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1](https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1), with a test will at [will/1](https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1:will/1)
- The Keeper's Board: [gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/keepersboard/v1](https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/keepersboard/v1)

The same paths without `/v1` hold an earlier version, without the objection period, `Hide`, `Decline`, `ReturnRights` and `ClaimAll`. Packages on gno.land cannot be changed once added; do not build on the old paths.

## Why

When an owner dies or loses their key, their funds stay where they are and a realm they administer can no longer be updated. Heirloom hands both over without a trusted third party, after a silence the owner chose and a week in which they can still object.

## How it works

1. **Make a will.** Heirs are `address:percent` pairs adding up to 100, at most 10. The silence period is 1 to 3650 days. A successor is optional. One unreleased will per owner.
2. **Fill it.** Deposit GNOT with the call, or any GRC20 token from `grc20reg` after approving Heirloom as a spender. At most 10 different assets.
3. **Stay alive.** A sign of life is any call you sign with your master key to Heirloom, or to a realm that calls `heirloom.Touch`. Session keys and other activity on the chain do not count.
4. **Ask to release.** After the silence period, anyone but the owner calls `Release`. Nothing is frozen or paid yet.
5. **Object.** For 7 days, and after that until someone completes the release, any sign of life from the owner cancels the request.
6. **Release.** After the 7 days, the next `Release` (or `Claim`) releases the will. It is frozen from then on.
7. **Pay out.** Anyone can pay an heir with `Claim(id, heir, asset)` or `ClaimAll(id, heir)`; the money always goes to the heir. Shares are rounded down and the first heir gets the remainder.
8. **Hand over admin rights.** Releasing the will hands the owner's admin rights to the successor.

### Admin rights and `Holder`

`heirloom.Holder(addr)` returns `addr`, or the end of the chain of handovers that starts at `addr`: if your successor's own will is released later, your rights follow theirs. A handover that would loop back to the owner is skipped. A named successor can `Decline` before release, and the successor who received the rights can `ReturnRights` to the owner after release; without that, the handover stays. Only the first released will of an owner hands rights over, unless they were returned.

A realm opts in by checking `Holder` instead of a fixed address:

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

## Using it

The realm pages in gnoweb have forms and links for every action: make a will on the home page, manage it on `:will/<id>`, and see the wills you made or that name you on `:u/<address>`.

With gnokey:

```sh
PKG=gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1

# a will with two heirs, 180 days of silence and a successor
gnokey maketx call -pkgpath $PKG -func CreateWill \
  -args "g1heir...:70, g1other...:30" -args "180" -args "g1successor..." \
  -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid <chain> -remote <rpc> mykey

# put 5 GNOT into will 1
gnokey maketx call -pkgpath $PKG -func Deposit -args 1 -send 5000000ugnot ...

# after the silence period: ask to release will 1, prints ("requested" string)
gnokey maketx call -pkgpath $PKG -func Release -args 1 ...

# 7 days later: release it, prints ("released" string), then pay an heir everything
gnokey maketx call -pkgpath $PKG -func Release -args 1 ...
gnokey maketx call -pkgpath $PKG -func ClaimAll -args 1 -args "g1heir..." ...
```

## API

| Function | Who can call it | What it does |
| :--- | :--- | :--- |
| `CreateWill(heirs, silence, successor) int` | anyone | Makes your will. |
| `SetHeirs(id, heirs)`, `SetSuccessor(id, successor)`, `SetSilence(id, silence)` | owner | Change the will. |
| `Ping(id)` | owner | Sign of life; cancels a release request. |
| `Deposit(id)` | owner, direct call | Adds the GNOT sent with the call. |
| `DepositToken(id, token, amount)` | owner | Pulls an approved GRC20 amount into the will. |
| `Withdraw(id, asset, amount)` | owner | Sends an asset back to the owner. |
| `Revoke(id)` | owner | Returns everything and deletes the will. |
| `Release(id) string` | anyone but the owner | Asks to release, or releases after 7 days; returns `requested` or `released`. |
| `Claim(id, heir, asset)`, `ClaimAll(id, heir)` | anyone, except the owner before release | Pays an heir's share of one asset, or of all. |
| `Hide(id)`, `Unhide(id)` | an heir or successor | Takes a will off your `:u/<address>` page, or puts it back. |
| `Decline(id)` | the successor, before release | Stops being the successor; the owner cannot name you again. |
| `ReturnRights(owner)` | the successor who received them | Gives the admin rights back to the owner. |
| `Touch()` | any realm | Sign of life for the transaction signer. |
| `Holder(addr) address` | read | Who holds the admin rights of `addr`. |
| `ActiveWill(owner) (id, ok)`, `WillInfo(id) (owner, status, releaseAt, ok)` | read | The owner's unreleased will; status `active`, `due`, `requested` or `released`. |
| `HomeURL()`, `WillURL(id)`, `UserURL(addr)` | read | gnoweb paths, for links from other realms. |

Owner calls, `ReturnRights` and `CreateWill` need the master key; owner calls are refused once the will is released. Amounts are in the asset's smallest unit (1 GNOT = 1000000 ugnot).

## The Keeper's Board

`demo/keepersboard` is a notice board whose keeper is `heirloom.Holder(founder)`, where the founder is the address in the board's package path; the board refuses to deploy under a path that does not start with an address. Anyone can post a note; the keeper pins one note and removes any. Every post, pin and removal calls `heirloom.Touch`. When the founder's will is released, the board passes to the successor with no change to its code.

## Design notes

- **Who is calling.** Entry points check `cur.IsCurrent()` and take the caller from `cur.Previous()`, so a realm the owner happens to call cannot act as the owner. `Release` and `Claim` refuse the owner both as that caller and as the signer of the transaction.
- **Signs of life follow the signer** (`OriginCaller`), even through another realm. That can only extend the signer's own will.
- **Coins** are accepted only by `Deposit`, and only on a direct call (`IsUserCall`), so a `maketx run` script or another realm cannot reuse the coins attached to a transaction.
- **Objection period.** Asking to release and releasing are two calls, 7 days apart, with a public `ReleaseRequested` event in between.
- **A released will is frozen.** Shares are computed from what it held at release; a claim marks the heir as paid.
- **`chain/runtime/unsafe`** is imported for `OriginSend`, read only behind `IsUserCall`, and for `OriginCaller`, used for signs of life and to keep the signing owner from releasing their own will.

## Known limitations

- Admin rights pass only in realms that check `Holder`.
- An owner who is active on the chain only through bank sends, other realms or a session key still loses the admin rights after the silence period and the 7 days, unless the successor returns them.
- Tokens of all wills sit at the realm's address. If a token's issuer takes or burns tokens from it, withdrawals and claims of that token succeed first come, first served until the realm runs short; other assets are not affected.
- Coins or tokens sent to the realm's address directly, not with `Deposit` or `DepositToken`, belong to no will and cannot be recovered.
- With GNOT transfers restricted on the network (`ugnot` in the bank's `restricted_denoms`), GNOT cannot be withdrawn, revoked or claimed until the restriction is lifted; those calls fail without changing anything, and `Release` still works. Onyx and mainnet had no restricted denoms in November 2026.
- Anyone can name any address as an heir or successor. The address can hide the will from its page and decline the succession; it cannot stop being an heir.
- `Holder` follows the chain of handovers one step per handover.

## Storage

Storage deposits are paid by whoever signs the call. Measured in `integration/heirloom_audit.txtar` (2 heirs, a successor, GNOT and one token), at 100 ugnot per byte as on Onyx:

| Call | Stored |
| :--- | ---: |
| `CreateWill` | 14.3 KB |
| `Deposit` | 1.0 KB |
| `Release`, request | 0.2 KB |
| `Release`, release | 1.8 KB |
| `Claim` / `ClaimAll` | 1 to 4 KB |

The owner's deposit is refunded on `Revoke`, not after release.

## Tests

Copy the realm to `examples/gno.land/r/<namespace>/heirloom/v1` and `demo/keepersboard` to `examples/gno.land/r/<namespace>/keepersboard/v1` in a gno checkout, then from `examples`:

```sh
gno test ./gno.land/r/<namespace>/heirloom/v1/
gno test ./gno.land/r/<namespace>/keepersboard/v1/
```

Heirloom has 46 unit tests and the board 5: release and objection, payouts and rounding, admin succession, returning and declining rights, calls through other realms, and the rendered pages. The 10-asset limit is tested on the will's bookkeeping, not with 11 real tokens.

Four integration tests in [`integration/`](integration) run on a real in-memory gno v1.8.0 node, with a day patched to 30 seconds:

- `heirloom_audit.txtar`: refused coin tricks and calls through other realms, GRC20 deposits, the objection period, release and payout of both assets.
- `heirloom_session.txtar`: what a session key can and cannot do.
- `heirloom_multimsg.txtar`: coins in transactions with several messages.
- `heirloom_locked.txtar`: restricted GNOT transfers.

Copy them to `gno.land/pkg/integration/testdata/` in a checkout that also holds the realm, then run `go test ./gno.land/pkg/integration/ -run 'TestTestdata/heirloom_'`. They wait with `exec sleep`.

## License

MIT, see [LICENSE](LICENSE).
