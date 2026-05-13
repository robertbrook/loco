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
- Expressions (`sum`, `difference`, `product`, `quotient`, `remainder`, `power`, `abs`, `sqrt`, trig/log)
- Word/list operations (`word`, `list`, `sentence`, `first`, `last`, `butfirst`, `butlast`, `item`, `count`)
- Predicates and logic (`lessp`, `greaterp`, `equalp`, `emptyp`, `numberp`, `wordp`, `listp`, `and`, `or`, `not`)
- Control flow (`repeat`, `if`, `ifelse`, `run`, `catch`, `throw`)
- User procedures (`to`, `end`, `output`, `stop`)
- Property lists (`putProp`, `getProp`, `remProp`, `propList`)
- Console and text I/O (`print`, `show`, `type`, `readWord`, `readChar`, `readChars`, `readList`)
- Utility words (`wait`, `date`, `time`, `words`)

## Test

```sh
make test
```
