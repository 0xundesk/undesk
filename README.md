# RATCHET

Your high becomes your floor.

[x.com/0xundesk](https://x.com/0xundesk)

A bank sells this as a lookback put with a rolling strike, on a desk full of
people. This is that desk with nobody at it.

Put in stock, and the cash the starting floor costs. From that moment the
vault has one job: at every price the chain publishes, move a little between
stock and cash so that it holds what "the stock, but never below the floor"
pays, and when the stock climbs, drag the floor up behind it and lock it. A
ratchet turns one way. The floor only ever rises.

## Live on Hood Chain

    Ratchet  0xDC3d4f67F9AD517336f2db084dc05f30d2b63112
    Venue    0x5378Fa5716dd2150011928D4224311417673fDAb
    Chain    Hood Chain (id 4663)

## The proof

Black and Scholes showed that an option can be built out of stock and cash
alone. The formula is the consequence. This machine builds the option, and
the ratchet adds one line: whenever the price has climbed enough that a fresh
at-the-money put fits inside the vault with room, the floor is re-struck at
the new price and the guarantee is locked to the new number.

Two numbers say whether the underlying replication works, both from outside
this repository. The textbook value of a standard call is 7.965567455405804.
This engine, in integers only, answers 7.965579. The prints published on
this chain, 992 of them across 74 days, are packed into the test suite.
Twelve month-long windows replay from the tape with a fixed floor. The
manufactured payoff lands within 2.52 percent of what the option owed, the
median across every window, at the thirteen chances a day this chain gives.

## The ratchet on the same tape

Twelve month-long windows again, with clicks turned on and a two percent
minimum bump per click. Each window's floor starts at spot, and every click
demands that a fresh at-the-money put fits inside the vault with headroom
before it fires. The measured result:

    median clicks per 30 days                  1
    median floor rise over the month           7.6%
    median finish above the locked floor       3.9%

Eleven of twelve windows finished comfortably above their locked floor. One
did not, by 10 percent, in the same fast-tape window where the underlying
replication itself missed by that much. The floor is a monotone promise by
construction. Defending it is a physics question, and the physics does not
change: the same 2.52 percent hedge error a fixed floor carries, the moving
floor carries too, plus a tail.

## The desk staffs itself

Every move is a transaction. Anyone may push the button once the position
has drifted past its band, or once the ratchet has a click waiting. The
vault pays the pusher out of its own cash. The machine hires its own staff,
one transaction at a time.

## What is inside

The EVM has no decimal point, so it has no logarithm, no exponential, no
square root, no bell curve. RATCHET carries its own, in 1e18 fixed point:
the log by an atanh series, e^x by argument reduction and a Taylor series,
the normal curve by Abramowitz and Stegun, good to seven decimal places.

- `Fixed.sol` and `BS.sol` - the arithmetic and the Black-Scholes core
- `Ratchet.sol` - the vault: stock in, floor named, clicks and drifts
  handled by anyone, closed after expiry
- `Venue.sol` - the bridge to the Uniswap V3 style pool where the two legs
  actually trade, with a callback that only pays out while the vault's own
  swap is in flight

The weight the vault targets is always between zero and one, so it never
borrows and never shorts.

## Interface

    quote(shares, floor, expiry, vol)                        -> cost of the initial floor
    open(shares, cash, floor, expiry, vol, band, lift)       -> id
    click(id)                                                -> new floor waiting to lock, or two zeros
    target(id)                                               -> the weight that belongs in stock
    weight(id)                                               -> the weight that is in stock
    value(id)                                                -> what the vault is worth
    rebalance(id)                                            -> anyone, once click or drift has room
    close(id)                                                -> after expiry, everything to the owner

Setting `lift` to the maximum keeps the floor fixed. That is the plain
UNDESK behaviour: same code, no ratchet.

## Build and test

    forge test

Every expected value is a closed form, a hand inversion, or the market that
actually happened. Nothing is mocked.

MIT licensed.
