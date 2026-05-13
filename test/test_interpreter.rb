require_relative 'test_helper'

class TestInterpreter < Minitest::Test
  def setup
    @i = Loco::Interpreter.new
  end

  def run_logo(code)
    @i.run(code)
  end

  def eval_logo(code)
    @i.eval_str(code)
  end

  # ===== ARITHMETIC =====

  def test_basic_arithmetic
    assert_equal 5, eval_logo("2 + 3")
    assert_equal 6, eval_logo("2 * 3")
    assert_equal 1, eval_logo("3 - 2")
    assert_equal 2, eval_logo("6 / 3")
    assert_equal 7, eval_logo("SUM 3 4")
    assert_equal 6, eval_logo("PRODUCT 2 3")
  end

  def test_arithmetic_precedence
    assert_equal 7, eval_logo("1 + 2 * 3")
    assert_equal 9, eval_logo("(1 + 2) * 3")
    assert_equal 5, eval_logo("1 + 2 + 2")
  end

  def test_division
    assert_equal 2, eval_logo("6 / 3")
    result = eval_logo("7 / 2")
    # Can be integer or float depending on impl
    assert_in_delta 3.5, result.to_f, 0.001
  end

  def test_unary_minus
    assert_equal(-3, eval_logo("MINUS 3"))
    assert_equal(-5, eval_logo("0 - 5"))
  end

  def test_math_functions
    assert_in_delta 2.0, eval_logo("SQRT 4"), 0.001
    assert_equal 8, eval_logo("POWER 2 3")
    assert_in_delta 1.0, eval_logo("SIN 90"), 0.001
    assert_in_delta 1.0, eval_logo("COS 0"), 0.001
  end

  def test_remainder_modulo
    assert_equal 1, eval_logo("REMAINDER 7 3")
    assert_equal 1, eval_logo("MODULO 7 3")
    assert_equal(-1, eval_logo("REMAINDER -7 3"))
    assert_equal 2, eval_logo("MODULO -7 3")
  end

  def test_int_round
    assert_equal 3, eval_logo("INT 3.7")
    assert_equal(-3, eval_logo("INT -3.7"))
    assert_equal 4, eval_logo("ROUND 3.7")
    assert_equal 4, eval_logo("ROUND 3.5")
  end

  def test_random
    result = eval_logo("RANDOM 10")
    assert result.is_a?(Integer)
    assert result >= 0
    assert result < 10
  end

  # ===== VARIABLES =====

  def test_make_and_thing
    run_logo("MAKE \"X 42")
    assert_equal 42, eval_logo(":X")
    assert_equal 42, eval_logo("THING \"X")
  end

  def test_make_word
    run_logo('MAKE "NAME "LOGO')
    assert_equal "LOGO", eval_logo(":NAME")
  end

  def test_local
    run_logo("MAKE \"G 10")
    run_logo("TO TESTLOCAL\nLOCAL \"G\nMAKE \"G 99\nEND")
    run_logo("TESTLOCAL")
    assert_equal 10, eval_logo(":G")
  end

  def test_localmake
    run_logo("TO TESTLM\nLOCALMAKE \"X 5\nEND")
    run_logo("TESTLM")
    # X should not be visible outside
    assert_raises(Loco::LogoError) { eval_logo(":X") }
  end

  # ===== DATA STRUCTURES =====

  def test_list_creation
    result = eval_logo("[1 2 3]")
    assert_equal [1, 2, 3], result
  end

  def test_word_creation
    assert_equal "hello", eval_logo('"hello')
    assert_equal "HELLO", eval_logo("WORD \"HE \"LLO")
  end

  def test_list_primitives
    result = eval_logo("LIST 1 2")
    assert_equal [1, 2], result
  end

  def test_fput_lput
    assert_equal [1, 2, 3], eval_logo("FPUT 1 [2 3]")
    assert_equal [1, 2, 3], eval_logo("LPUT 3 [1 2]")
  end

  def test_first_last
    assert_equal 1, eval_logo("FIRST [1 2 3]")
    assert_equal 3, eval_logo("LAST [1 2 3]")
    assert_equal "h", eval_logo('FIRST "hello')
  end

  def test_butfirst_butlast
    assert_equal [2, 3], eval_logo("BUTFIRST [1 2 3]")
    assert_equal [1, 2], eval_logo("BUTLAST [1 2 3]")
    assert_equal "ello", eval_logo('BUTFIRST "hello')
  end

  def test_item
    assert_equal 2, eval_logo("ITEM 2 [1 2 3]")
    assert_equal "e", eval_logo('ITEM 2 "hello')
  end

  def test_count
    assert_equal 3, eval_logo("COUNT [1 2 3]")
    assert_equal 5, eval_logo('COUNT "hello')
  end

  def test_sentence
    result = eval_logo("SENTENCE [1 2] [3 4]")
    assert_equal [1, 2, 3, 4], result

    result = eval_logo("SENTENCE 1 [2 3]")
    assert_equal [1, 2, 3], result
  end

  def test_member
    result = eval_logo("MEMBER 2 [1 2 3]")
    assert_equal [2, 3], result
  end

  def test_reverse
    assert_equal [3, 2, 1], eval_logo("REVERSE [1 2 3]")
    assert_equal "cba", eval_logo('REVERSE "abc')
  end

  # ===== PREDICATES =====

  def test_wordp
    assert_equal 'true', eval_logo('WORDP "hello')
    assert_equal 'true', eval_logo('WORDP 42')
    assert_equal 'false', eval_logo('WORDP [1 2]')
  end

  def test_listp
    assert_equal 'true', eval_logo('LISTP [1 2]')
    assert_equal 'false', eval_logo('LISTP "hello')
  end

  def test_numberp
    assert_equal 'true', eval_logo('NUMBERP 42')
    assert_equal 'true', eval_logo('NUMBERP "42')
    assert_equal 'false', eval_logo('NUMBERP "hello')
  end

  def test_emptyp
    assert_equal 'true', eval_logo('EMPTYP []')
    assert_equal 'true', eval_logo('EMPTYP ""')
    assert_equal 'false', eval_logo('EMPTYP [1]')
  end

  def test_equalp
    assert_equal 'true', eval_logo('EQUALP 3 3')
    assert_equal 'false', eval_logo('EQUALP 3 4')
    assert_equal 'true', eval_logo('"hello = "hello')
    assert_equal 'false', eval_logo('"hello = "world')
  end

  def test_comparisons
    assert_equal 'true', eval_logo('LESSP 2 3')
    assert_equal 'false', eval_logo('LESSP 3 2')
    assert_equal 'true', eval_logo('GREATERP 3 2')
    assert_equal 'true', eval_logo('2 < 3')
    assert_equal 'true', eval_logo('3 > 2')
  end

  def test_memberp
    assert_equal 'true', eval_logo('MEMBERP 2 [1 2 3]')
    assert_equal 'false', eval_logo('MEMBERP 5 [1 2 3]')
  end

  # ===== CONTROL =====

  def test_if
    run_logo("MAKE \"R 0")
    run_logo('IF EQUALP 1 1 [MAKE "R 1]')
    assert_equal 1, eval_logo(":R")
  end

  def test_if_else
    run_logo("MAKE \"R 0")
    run_logo('IFELSE EQUALP 1 2 [MAKE "R 1] [MAKE "R 2]')
    assert_equal 2, eval_logo(":R")
  end

  def test_repeat
    run_logo("MAKE \"R 0")
    run_logo('REPEAT 5 [MAKE "R :R + 1]')
    assert_equal 5, eval_logo(":R")
  end

  def test_repcount
    run_logo("MAKE \"LAST 0")
    run_logo("REPEAT 3 [MAKE \"LAST REPCOUNT]")
    assert_equal 3, eval_logo(":LAST")
  end

  def test_run
    run_logo("MAKE \"R 0")
    run_logo('RUN [MAKE "R 99]')
    assert_equal 99, eval_logo(":R")
  end

  def test_catch_throw
    # THROW with value needs parens to read 2 args
    result = eval_logo('CATCH "TAG [(THROW "TAG 42)]')
    assert_equal 42, result
  end

  def test_stop
    run_logo("TO TESTSTOP\nMAKE \"X 1\nSTOP\nMAKE \"X 2\nEND")
    run_logo("MAKE \"X 0")
    run_logo("TESTSTOP")
    assert_equal 1, eval_logo(":X")
  end

  def test_output
    run_logo("TO DOUBLE :N\nOUTPUT :N * 2\nEND")
    result = eval_logo("DOUBLE 5")
    assert_equal 10, result
  end

  # ===== PROCEDURES =====

  def test_define_procedure
    run_logo("TO SQUARE :N\nOUTPUT :N * :N\nEND")
    assert_equal 9, eval_logo("SQUARE 3")
    assert_equal 25, eval_logo("SQUARE 5")
  end

  def test_recursive_procedure
    run_logo("TO FACT :N\nIF :N = 0 [OUTPUT 1]\nOUTPUT :N * FACT :N - 1\nEND")
    assert_equal 1, eval_logo("FACT 0")
    assert_equal 6, eval_logo("FACT 3")
    assert_equal 120, eval_logo("FACT 5")
  end

  def test_procedure_with_multiple_args
    run_logo("TO ADD :A :B\nOUTPUT :A + :B\nEND")
    assert_equal 7, eval_logo("ADD 3 4")
  end

  # ===== LOGICAL =====

  def test_and
    assert_equal 'true', eval_logo('AND "true "true')
    assert_equal 'false', eval_logo('AND "true "false')
    assert_equal 'false', eval_logo('AND "false "true')
  end

  def test_or
    assert_equal 'true', eval_logo('OR "true "false')
    assert_equal 'true', eval_logo('OR "false "true')
    assert_equal 'false', eval_logo('OR "false "false')
  end

  def test_not
    assert_equal 'false', eval_logo('NOT "true')
    assert_equal 'true', eval_logo('NOT "false')
  end

  # ===== STRING OPERATIONS =====

  def test_uppercase_lowercase
    assert_equal "HELLO", eval_logo('UPPERCASE "hello')
    assert_equal "hello", eval_logo('LOWERCASE "HELLO')
  end

  def test_ascii_char
    assert_equal 65, eval_logo('ASCII "A')
    assert_equal "A", eval_logo('CHAR 65')
  end

  # ===== ARRAYS =====

  def test_array_creation
    result = eval_logo("ARRAY 3")
    assert result.is_a?(Loco::LogoArray)
    assert_equal 3, result.size
  end

  def test_array_setitem
    run_logo("MAKE \"A ARRAY 3")
    run_logo("SETITEM 1 :A 10")
    run_logo("SETITEM 2 :A 20")
    run_logo("SETITEM 3 :A 30")
    assert_equal 10, eval_logo("ITEM 1 :A")
    assert_equal 20, eval_logo("ITEM 2 :A")
    assert_equal 30, eval_logo("ITEM 3 :A")
  end

  def test_listtoarray
    result = eval_logo("LISTTOARRAY [1 2 3]")
    assert result.is_a?(Loco::LogoArray)
    assert_equal 3, result.size
    assert_equal 1, result[1]
    assert_equal 2, result[2]
    assert_equal 3, result[3]
  end

  def test_arraytolist
    run_logo("MAKE \"A ARRAY 2")
    run_logo("SETITEM 1 :A 10")
    run_logo("SETITEM 2 :A 20")
    result = eval_logo("ARRAYTOLIST :A")
    assert_equal [10, 20], result
  end

  # ===== WORKSPACE MANAGEMENT =====

  def test_procedurep
    run_logo("TO MYPROC\nOUTPUT 1\nEND")
    assert_equal 'true', eval_logo('PROCEDUREP "MYPROC')
    assert_equal 'false', eval_logo('PROCEDUREP "NOEXIST')
  end

  def test_primitivep
    assert_equal 'true', eval_logo('PRIMITIVEP "PRINT')
    assert_equal 'false', eval_logo('PRIMITIVEP "NOEXIST')
  end

  def test_namep
    run_logo('MAKE "MYVAR 42')
    assert_equal 'true', eval_logo('NAMEP "MYVAR')
    assert_equal 'false', eval_logo('NAMEP "NOVAR')
  end

  def test_erase
    run_logo("TO TEMPPROC\nOUTPUT 1\nEND")
    run_logo('ERASE [[TEMPPROC] [] []]')
    assert_equal 'false', eval_logo('PROCEDUREP "TEMPPROC')
  end

  # ===== PROPERTY LISTS =====

  def test_property_lists
    run_logo('PPROP "PERSON "NAME "Alice')
    run_logo('PPROP "PERSON "AGE 30')
    assert_equal "Alice", eval_logo('GPROP "PERSON "NAME')
    assert_equal 30, eval_logo('GPROP "PERSON "AGE')
    run_logo('REMPROP "PERSON "AGE')
    assert_equal [], eval_logo('GPROP "PERSON "AGE')
  end

  # ===== TEMPLATE ITERATION =====

  def test_map
    result = eval_logo("MAP [? * 2] [1 2 3]")
    assert_equal [2, 4, 6], result
  end

  def test_filter
    result = eval_logo("FILTER [? > 2] [1 2 3 4]")
    assert_equal [3, 4], result
  end

  def test_reduce
    result = eval_logo("REDUCE [?1 + ?2] [1 2 3 4]")
    assert_equal 10, result
  end

  def test_apply
    run_logo("TO MYSUM :A :B\nOUTPUT :A + :B\nEND")
    result = eval_logo('APPLY "MYSUM [3 4]')
    assert_equal 7, result
  end

  # ===== FOR LOOP =====

  def test_for_loop
    run_logo("MAKE \"SUM 0")
    run_logo("FOR [I 1 5] [MAKE \"SUM :SUM + :I]")
    assert_equal 15, eval_logo(":SUM")
  end

  # ===== WHILE LOOP =====

  def test_while_loop
    run_logo("MAKE \"N 0")
    run_logo("MAKE \"S 0")
    run_logo("WHILE [:N < 5] [MAKE \"N :N + 1  MAKE \"S :S + :N]")
    assert_equal 15, eval_logo(":S")
  end

  # ===== GOTO/TAG =====

  def test_goto_tag
    run_logo("TO TESTGOTO\nMAKE \"X 0\nTAG \"START\nMAKE \"X :X + 1\nIF :X < 3 [GOTO \"START]\nOUTPUT :X\nEND")
    result = eval_logo("TESTGOTO")
    assert_equal 3, result
  end

  # ===== RUNRESULT =====

  def test_runresult_with_output
    run_logo("TO RR_TEST\nOUTPUT 42\nEND")
    result = eval_logo("RUNRESULT [RR_TEST]")
    assert_equal [42], result
  end

  def test_runresult_without_output
    result = eval_logo("RUNRESULT [MAKE \"X 1]")
    assert_equal [], result
  end

  # ===== TEST/IFTRUE/IFFALSE =====

  def test_test_iftrue_iffalse
    run_logo("MAKE \"R 0")
    run_logo("TEST EQUALP 2 2")
    run_logo('IFTRUE [MAKE "R 1]')
    run_logo('IFFALSE [MAKE "R 2]')
    assert_equal 1, eval_logo(":R")
  end

  # ===== BITWISE =====

  def test_bitwise
    assert_equal 4, eval_logo("BITAND 6 5")
    assert_equal 7, eval_logo("BITOR 6 5")
    assert_equal 3, eval_logo("BITXOR 6 5")
    assert_equal 4, eval_logo("ASHIFT 1 2")
  end

  # ===== WORD/STRING OPS =====

  def test_parse
    result = eval_logo('PARSE "1 2 3')
    # Parse of "1 2 3" means parse the word "1" -> [1]
    # Actually PARSE parses a single word as a list
    assert_kind_of Array, result
  end

  def test_word_concat
    assert_equal "helloworld", eval_logo('WORD "hello "world')
  end
end
