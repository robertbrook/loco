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
- Arithmetic and math (`sum`, `difference`, `product`, `quotient`, `remainder`, `power`, `minus`, `abs`, `sqrt`, trig)
- Comparisons and logic (`lessp`/`less?`, `greaterp`/`greater?`, `equalp`/`equal?`, `and`, `or`, `not`)
- Words/lists (`word`, `list`, `sentence`/`se`, `first`, `last`, `butfirst`/`bf`, `butlast`/`bl`, `count`, `item`, predicates)
- Control flow (`repeat`, `if`, `ifelse`, `run`, `wait`)
- User procedures (`to`, `end`, `output`, `stop`)
- Console output (`print`/`pr`, `show`, `type`)

## Test

```sh
make test
```
