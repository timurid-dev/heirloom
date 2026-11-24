# Heirloom

Heirloom is a will for gno.land. You leave your GNOT and GRC20 tokens to the people you choose, and you can name a successor who takes over your admin rights in other realms. Until you go silent for the period you set, everything stays yours: you can deposit, withdraw, change heirs or revoke the will at any time.

Built for the Gnome Tavern hackathon. The repository also contains **The Keeper's Board**, a small demo realm whose admin passes to a successor through Heirloom.

## Live on the Onyx testnet

- Heirloom: https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom
- The Keeper's Board: https://onyx.testnets.gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/keepersboard

## Why

On a chain, a lost key or a death is permanent. Funds sit untouched forever, and a realm whose admin is gone can never be updated again. Heirloom gives both a way out that needs no trusted third party: if the owner shows no sign of life for long enough, anyone can open the will, the heirs are paid, and the admin rights move to the successor.

## How it works

1. **Make a will.** List heirs as `address:percent` pairs that add up to 100 (at most 10 heirs), choose a silence period from 1 to 3650 days, and optionally name a successor. You can have one unreleased will at a time.
2. **Fill it.** Deposit GNOT with the call, or deposit any GRC20 token registered in `grc20reg` after approving Heirloom as a spender. A will holds at most 10 different assets.
3. **Stay alive.** Every successful call you sign to Heirloom restarts the clock: `Ping`, a deposit, a change of heirs. So does using any realm that calls `heirloom.Touch`, such as The Keeper's Board. Transactions signed with a session key do not count, and a session key cannot create or change a will.
4. **Release.** Once the silence period has passed, anyone but the owner can call `Release`. The will is frozen as it stands: from then on nobody can deposit, withdraw or change it.
5. **Pay out.** Anyone can call `Claim(id, heir, asset)` to send an heir's share of one asset to that heir. The share always goes to the heir, so heirs that are realms, or that lost their key, can still be paid. Shares are rounded down and the first heir gets the remainder, so payouts add up exactly to what the will held.
6. **Hand over admin rights.** Releasing a will hands the owner's admin rights to the successor, once and for good. If a later will of the same owner is released, it only leaves assets.

### Admin rights and `Holder`

`heirloom.Holder(addr)` returns who holds the admin rights of `addr`: `addr` itself until a released will of `addr` hands them on, then whoever holds the rights of that successor. Handovers chain: if your successor's own will is released later, your rights follow theirs. A handover that would loop back to the owner is refused, and the owner keeps the rights.

Heirloom does not change other realms by itself. A realm opts in by checking `Holder` instead of a fixed address:

```go
import "gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom"

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
PKG=gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom

# a will with two heirs, 180 days of silence and a successor
gnokey maketx call -pkgpath $PKG -func CreateWill \
  -args "g1heir...:70, g1other...:30" -args "180" -args "g1successor..." \
  -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid <chain> -remote <rpc> mykey

# put 5 GNOT into will 1
gnokey maketx call -pkgpath $PKG -func Deposit -args 1 -send 5000000ugnot ...

# after the silence period, anyone but the owner
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
| `Ping(id)` | owner | Restarts the silence period. |
| `Deposit(id)` | owner, direct call | Adds the GNOT sent with the call. |
| `DepositToken(id, token, amount)` | owner | Pulls an approved GRC20 amount into the will. |
| `Withdraw(id, asset, amount)` | owner | Sends an asset back to the owner. |
| `Revoke(id)` | owner | Returns everything and deletes the will. |
| `Release(id)` | anyone but the owner | Opens a will whose silence period has passed. |
| `Claim(id, heir, asset)` | anyone, except the owner before release | Pays one heir's share of one asset. |
| `Touch()` | any realm | Sign of life for the transaction signer. |
| `Holder(addr) address` | read | Who holds the admin rights of `addr`. |
| `ActiveWill(owner) (id, ok)` | read | The owner's unreleased will. |
| `WillInfo(id) (owner, status, releaseAt, ok)` | read | Status: `active`, `due` or `released`. |

Owner calls need the master key and are refused once the will is released. Amounts are in the asset's smallest unit (1 GNOT = 1000000 ugnot).

## The Keeper's Board

`demo/keepersboard` is a notice board whose keeper is `heirloom.Holder(founder)`, where the founder is the owner of the namespace the board is deployed under. Anyone can post a note; the keeper pins one note and removes any. Every post, pin and removal calls `heirloom.Touch`. When the founder's will is released, the board passes to the founder's successor with no change to the board's code, and its page says so.

## Design notes

- **Who is calling.** Every entry point checks `cur.IsCurrent()` before reading `cur.Previous()`. Owner actions compare the owner with that immediate caller, so a realm that the owner happens to call cannot act as the owner.
- **Signs of life follow the signer.** `Touch`, `Release` and `Claim` credit the account that signed the transaction (`OriginCaller`), even when the call comes through another realm. That can only extend the signer's own will; it never grants owner rights.
- **Coins.** GNOT is accepted only on a direct call (`IsUserCall`), so a `maketx run` script or another realm cannot reuse the coins attached to a transaction. Every other function refuses coins sent with a direct call.
- **Admin succession** is stored as a union-find: addresses whose rights end with the same holder share a group, so `Holder` answers in a few steps however long the chain of handovers grows, and a loop is detected by comparing two groups.
- **Why `chain/runtime/unsafe` is imported.** `OriginSend` is the only way to read the GNOT attached to a call, and it is read only behind `IsUserCall`. `OriginCaller` is used only for signs of life, as above.

## Known limitations

- Tokens of all wills sit at the realm's single address. If a token's issuer can take or burn tokens from that address, `Withdraw` and `Revoke` of that token fail for the wills holding it. Other assets can still be withdrawn one by one, and sending the missing units back to the realm fixes it.
- Admin rights pass only in realms that check `Holder`. Realms built on `ownable` or a fixed admin address are not affected.
- The session-key rules are not covered by unit tests, because Gno's test package cannot simulate a session key. They rely on `runtime.GetSessionInfo` as documented in the standard library.
- The 10-asset limit is not covered by a test: the test environment has one GRC20 token.
- Storage deposit: a will with 2 heirs stores about 18 KB, with 10 heirs about 59 KB. It is refunded on `Revoke`, not after release.

## Tests

In a gno checkout, copy the realm files to `examples/gno.land/r/<namespace>/heirloom` and `demo/keepersboard` to `examples/gno.land/r/<namespace>/keepersboard`, with `<namespace>` matching the module paths in `gnomod.toml`. Then, from `examples`:

```sh
gno test ./gno.land/r/<namespace>/heirloom/
gno test ./gno.land/r/<namespace>/keepersboard/
```

Heirloom has 30 tests and The Keeper's Board has 2. They cover release and payout, rounding, admin succession through long chains and loops, a stranger trying to block a handover, calls made through other realms, deposit guards, and the rendered pages. `gno fmt` and `gno lint` are clean. The whole flow, from a pinned note to the board passing to the successor, was also run on a local `gnodev` node with real transactions.

## License

MIT, see [LICENSE](LICENSE).
