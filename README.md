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
- Expressions (`sum`, `difference`, `product`, `quotient`)
- Comparisons (`lessp`, `greaterp`, `equalp`)
- Control flow (`repeat`, `if`, `ifelse`)
- User procedures (`to`, `end`, `output`, `stop`)
- Console output (`print`)
- Quotations/lists (`[...]`, `run`)
- Macros (`macro`)

## Test

```sh
make test
```
