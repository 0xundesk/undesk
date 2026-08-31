# UNDESK

An option nobody wrote.

A bank manufactures this on a desk, with people at it. This is that desk with
nobody at it.

Put in stock and the cash the floor costs. From there the vault moves a little
between stock and cash at every price the chain publishes, so that at the end
it holds what "the stock, but never below the floor" pays.

There is no writer on the other side, no counterparty to trust and no promise
to enforce. The payoff is manufactured out of your own two assets, one print at
a time, and anyone can watch every move.

## The proof

Black and Scholes showed that an option can be built out of stock and cash
alone. The formula is the consequence, not the discovery. This is the building.

Two numbers say whether it works, and both come from outside this repository.

    textbook value of the standard call      7.965567455405804
    this engine, in integers only            7.965579

    replayed on 992 real prints from Hood Chain, 12 windows of 30 days
    the manufactured payoff lands within     4.08% of what the option owed

The prints are the ones Hood Chain published for NVIDIA, read off the feed at
`0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15` and packed into `test/History.sol`.
Nothing is simulated and nothing is sampled: the machine is replayed on the
market that actually happened.

## What it costs to run

The vault moves when the weight has drifted past a band, and whoever pushes the
button is paid out of the vault. Wider bands mean fewer pushes.

    band    pushes per 30 days    error       error with the pusher paid
    2%             213            4.67%              26.70%
    5%              46            6.32%              11.67%
    10%             12           13.16%              14.24%

Measured on a hundred shares, paying one dollar a push, which is what a
transaction costs on this chain. The push is a flat fee, so the larger the
position the smaller its share of the premium.

## What is inside

Everything is built from integers, because the machine it runs on has no
decimal point.

- `Fixed.sol` - the logarithm by argument reduction and an atanh series, the
  exponential by argument reduction and a Taylor series, the square root by
  Babylonian iteration, and the bell curve by the Abramowitz and Stegun
  rational approximation, all in 1e18 fixed point
- `BS.sol` - what an option is worth, and the fraction of a share you must
  hold to track it
- `Undesk.sol` - the vault: put stock in, name the floor and the day, and
  anyone may push the button when the weight has drifted

The weight the vault targets is always between zero and one, which is why this
machine never borrows and never sells short.

## Interface

    quote(shares, floor, expiry, vol)              -> cash the floor costs
    open(shares, cash, floor, expiry, vol, band)   -> id
    target(id)                                     -> the weight that belongs in stock
    weight(id)                                     -> the weight that is in stock
    value(id)                                      -> what the vault is worth
    rebalance(id)                                  -> anyone, once the drift passes the band
    close(id)                                      -> after expiry, everything to the owner

Rate is zero throughout. The cash leg is a stablecoin that pays nothing, and
pretending otherwise would put a number in the formula that nobody receives.

## Build and test

    forge test

Every test runs offline. The replay carries its own prices.

## Layout

    src/Fixed.sol        the arithmetic the EVM does not have
    src/BS.sol           price, delta, and the insured weight
    src/Undesk.sol       the vault
    test/Math.t.sol      every constant checked against a published value
    test/Replay.t.sol    the machine replayed on real prints
    test/History.sol     992 prints, packed

MIT licensed.




