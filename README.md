# loco

A small implementation of the Logo programming language in C (without graphics).

## Build

```sh
make
```

## Run

Interactive mode:

```sh
./loco
```

Script mode:

```sh
./loco path/to/program.logo
```

## Supported features

- Variables (`make`, `:name`, `thing`)
- Expressions (`sum`, `difference`, `product`, `quotient`, `remainder`, `modulo`, `power`, `sqrt`, `int`, `round`, `abs`, `minus`, `random`)
- Comparisons and logic (`lessp`, `greaterp`, `equalp`, `notequalp`, `and`, `or`, `not`)
- Word/data operations (`word`, `sentence`/`se`, `list`, `first`, `last`, `butfirst`/`bf`, `butlast`/`bl`, `item`, `count`, `member`, `memberp`, `numberp`, `wordp`, `listp`, `emptyp`)
- Control flow (`repeat`, `if`, `ifelse`)
- User procedures (`to`, `end`, `output`, `stop`)
- Console output (`print`, `type`, `show`)
- Local scope helpers (`local`, `localmake`)

## Test

```sh
make test
```
