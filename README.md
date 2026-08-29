# UNDESK

An option nobody wrote.

A bank manufactures this on a desk, with people at it. This is that desk with
nobody at it.

Put in stock and the cash the floor costs. From there the vault moves a little
between stock and cash at every price the chain publishes, so that at the end
it holds what "the stock, but never below the floor" pays.

## The proof

Black and Scholes showed that an option can be built out of stock and cash
alone. The formula is the consequence, not the discovery. This is the building.

    textbook value of the standard call      7.965567455405804
    this engine, in integers only            7.965579

## What it costs to run

    band    pushes per 30 days    error       error with the pusher paid
    2%             213            4.67%              26.70%
    5%              46            6.32%              11.67%
    10%             12           13.16%              14.24%
