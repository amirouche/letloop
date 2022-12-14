(library (srfi srfi-143-check)

  (export ~check-srfi-143-00 ~check-srfi-143-01 ~check-srfi-143-02 ~check-srfi-143-03 ~check-srfi-143-04 ~check-srfi-143-05
~check-srfi-143-06 ~check-srfi-143-07 ~check-srfi-143-08 ~check-srfi-143-09 ~check-srfi-143-10 ~check-srfi-143-11 ~check-srfi-143-12
~check-srfi-143-13 ~check-srfi-143-14 ~check-srfi-143-15 ~check-srfi-143-16 ~check-srfi-143-17 ~check-srfi-143-18 ~check-srfi-143-19
~check-srfi-143-20 ~check-srfi-143-21 ~check-srfi-143-22 ~check-srfi-143-23 ~check-srfi-143-24 ~check-srfi-143-25 ~check-srfi-143-26
~check-srfi-143-27 ~check-srfi-143-28 ~check-srfi-143-29 ~check-srfi-143-30 ~check-srfi-143-31 ~check-srfi-143-32 ~check-srfi-143-33
~check-srfi-143-34 ~check-srfi-143-35 ~check-srfi-143-36 ~check-srfi-143-37 ~check-srfi-143-38 ~check-srfi-143-39 ~check-srfi-143-40
~check-srfi-143-41 ~check-srfi-143-42 ~check-srfi-143-43 ~check-srfi-143-44 ~check-srfi-143-45 ~check-srfi-143-46 ~check-srfi-143-47
~check-srfi-143-48 ~check-srfi-143-49 ~check-srfi-143-50 ~check-srfi-143-51 ~check-srfi-143-52 ~check-srfi-143-53 ~check-srfi-143-54
~check-srfi-143-55 ~check-srfi-143-56 ~check-srfi-143-57 ~check-srfi-143-58 ~check-srfi-143-59 ~check-srfi-143-60 ~check-srfi-143-61
~check-srfi-143-62 ~check-srfi-143-63 ~check-srfi-143-64 ~check-srfi-143-65 ~check-srfi-143-66 ~check-srfi-143-67 ~check-srfi-143-68
~check-srfi-143-69 ~check-srfi-143-70 ~check-srfi-143-71 ~check-srfi-143-72 ~check-srfi-143-73 #;~check-srfi-143-74 ~check-srfi-143-75
~check-srfi-143-76 #;~check-srfi-143-77 #;~check-srfi-143-78 #;~check-srfi-143-79 #;~check-srfi-143-80 #;~check-srfi-143-81 #;~check-srfi-143-82
#;~check-srfi-143-83 #;~check-srfi-143-84 ~check-srfi-143-85 ~check-srfi-143-86 ~check-srfi-143-87 ~check-srfi-143-88 ~check-srfi-143-89
~check-srfi-143-90 #;~check-srfi-143-91 ~check-srfi-143-92 ~check-srfi-143-93 ~check-srfi-143-94 ~check-srfi-143-95 ~check-srfi-143-96
~check-srfi-143-97 ~check-srfi-143-98 ~check-srfi-143-99 ~check-srfi-143-100 ~check-srfi-143-101 ~check-srfi-143-102 ~check-srfi-143-103
~check-srfi-143-104 ~check-srfi-143-105 ~check-srfi-143-106 ~check-srfi-143-107 ~check-srfi-143-108 ~check-srfi-143-109 ~check-srfi-143-110
#;~check-srfi-143-111 #;~check-srfi-143-112 ~check-srfi-143-113 #;~check-srfi-143-114 #;~check-srfi-143-115 ~check-srfi-143-116 ~check-srfi-143-117
~check-srfi-143-118 ~check-srfi-143-119 ~check-srfi-143-120 ~check-srfi-143-121 ~check-srfi-143-122 ~check-srfi-143-123 ~check-srfi-143-124
~check-srfi-143-125 ~check-srfi-143-126 ~check-srfi-143-127 ~check-srfi-143-128 ~check-srfi-143-129 ~check-srfi-143-130 ~check-srfi-143-131
~check-srfi-143-132 ~check-srfi-143-133 ~check-srfi-143-134 ~check-srfi-143-135 ~check-srfi-143-136 ~check-srfi-143-137 ~check-srfi-143-138
~check-srfi-143-139 #;~check-srfi-143-140)

  (import (scheme base) (letloop check) (srfi srfi-143))

  (define ~check-srfi-143-00
    (check #t (fixnum? 32767)))

  (define ~check-srfi-143-01
    (check #f (fixnum? 1.1)))

  (define ~check-srfi-143-02
    (check #t (fx=? 1 1 1)))

  (define ~check-srfi-143-03
    (check #f (fx=? 1 2 2)))

  (define ~check-srfi-143-04
    (check #f (fx=? 1 1 2)))

  (define ~check-srfi-143-05
    (check #f (fx=? 1 2 3)))

  (define ~check-srfi-143-06
    (check #t (fx<? 1 2 3)))

  (define ~check-srfi-143-07
    (check #f (fx<? 1 1 2)))

  (define ~check-srfi-143-08
    (check #t (fx>? 3 2 1)))

  (define ~check-srfi-143-09
    (check #f (fx>? 2 1 1)))

  (define ~check-srfi-143-10
    (check #t (fx<=? 1 1 2)))

  (define ~check-srfi-143-11
    (check #f (fx<=? 1 2 1)))

  (define ~check-srfi-143-12
    (check #t (fx>=? 2 1 1)))

  (define ~check-srfi-143-13
    (check #f (fx>=? 1 2 1)))

  (define ~check-srfi-143-14
    (check '(#t #f) (list (fx<=? 1 1 2) (fx<=? 2 1 3))))

  (define ~check-srfi-143-15
    (check #t (fxzero? 0)))

  (define ~check-srfi-143-16
    (check #f (fxzero? 1)))

  (define ~check-srfi-143-17
    (check #f (fxpositive? 0)))

  (define ~check-srfi-143-18
    (check #t (fxpositive? 1)))

  (define ~check-srfi-143-19
    (check #f (fxpositive? -1)))

  (define ~check-srfi-143-20
    (check #f (fxnegative? 0)))

  (define ~check-srfi-143-21
    (check #f (fxnegative? 1)))

  (define ~check-srfi-143-22
    (check #t (fxnegative? -1)))

  (define ~check-srfi-143-23
    (check #f (fxodd? 0)))

  (define ~check-srfi-143-24
    (check #t (fxodd? 1)))

  (define ~check-srfi-143-25
    (check #t (fxodd? -1)))

  (define ~check-srfi-143-26
    (check #f (fxodd? 102)))

  (define ~check-srfi-143-27
    (check #t (fxeven? 0)))

  (define ~check-srfi-143-28
    (check #f (fxeven? 1)))

  (define ~check-srfi-143-29
    (check #t (fxeven? -2)))

  (define ~check-srfi-143-30
    (check #t (fxeven? 102)))

  (define ~check-srfi-143-31
    (check 4 (fxmax 3 4)))

  (define ~check-srfi-143-32
    (check 5 (fxmax 3 5 4)))

  (define ~check-srfi-143-33
    (check 3 (fxmin 3 4)))

  (define ~check-srfi-143-34
    (check 3 (fxmin 3 5 4)))

  (define ~check-srfi-143-35
    (check 7 (fx+ 3 4)))

  (define ~check-srfi-143-36
    (check 12 (fx* 4 3)))

  (define ~check-srfi-143-37
    (check -1 (fx- 3 4)))

  (define ~check-srfi-143-38
    (check -3 (fxneg 3)))

  (define ~check-srfi-143-39
    (check 7 (fxabs -7)))

  (define ~check-srfi-143-40
    (check 7 (fxabs 7)))

  (define ~check-srfi-143-41
    (check 1764 (fxsquare 42)))

  (define ~check-srfi-143-42
    (check 4 (fxsquare 2)))

  (define ~check-srfi-143-43
    (check 2 (fxquotient 5 2)))

  (define ~check-srfi-143-44
    (check -2 (fxquotient -5 2)))

  (define ~check-srfi-143-45
    (check -2 (fxquotient 5 -2)))

  (define ~check-srfi-143-46
    (check 2 (fxquotient -5 -2)))

  (define ~check-srfi-143-47
    (check 1 (fxremainder 13 4)))

  (define ~check-srfi-143-48
    (check -1 (fxremainder -13 4)))

  (define ~check-srfi-143-49
    (check 1 (fxremainder 13 -4)))

  (define ~check-srfi-143-50
    (check -1 (fxremainder -13 -4)))

  (define ~check-srfi-143-51
    (check 35 (let*-values (((root rem) (fxsqrt 32)))
               (* root rem))))
  (define ~check-srfi-143-52
    (check -1 (fxnot 0)))

  (define ~check-srfi-143-53
    (check  0 (fxand #b0 #b1)))

  (define ~check-srfi-143-54
    (check  6 (fxand 14 6)))

  (define ~check-srfi-143-55
    (check  14 (fxior 10 12)))

  (define ~check-srfi-143-56
    (check  6 (fxxor 10 12)))

  (define ~check-srfi-143-57
    (check 0 (fxnot -1)))

  (define ~check-srfi-143-58
    (check 9 (fxif 3 1 8)))

  (define ~check-srfi-143-59
    (check 0 (fxif 3 8 1)))

  (define ~check-srfi-143-60
    (check 2 (fxbit-count 12)))

  (define ~check-srfi-143-61
    (check 0 (fxlength 0)))

  (define ~check-srfi-143-62
    (check 8 (fxlength 128)))

  (define ~check-srfi-143-63
    (check 8 (fxlength 255)))

  (define ~check-srfi-143-64
    (check 9 (fxlength 256)))

  (define ~check-srfi-143-65
    (check -1 (fxfirst-set-bit 0)))

  (define ~check-srfi-143-66
    (check 0 (fxfirst-set-bit 1)))

  (define ~check-srfi-143-67
    (check 0 (fxfirst-set-bit 3)))

  (define ~check-srfi-143-68
    (check 2 (fxfirst-set-bit 4)))

  (define ~check-srfi-143-69
    (check 1 (fxfirst-set-bit 6)))

  (define ~check-srfi-143-70
    (check 0 (fxfirst-set-bit -1)))

  (define ~check-srfi-143-71
    (check 1 (fxfirst-set-bit -2)))

  (define ~check-srfi-143-72
    (check 0 (fxfirst-set-bit -3)))

  (define ~check-srfi-143-73
    (check 2 (fxfirst-set-bit -4)))

  (define ~check-srfi-143-74
    ;; TODO: investigate why this is not good
    (check #t (fxbit-set? 0 1)))

  (define ~check-srfi-143-75
    (check #f (fxbit-set? 1 1)))

  (define ~check-srfi-143-76
    (check #f (fxbit-set? 1 8)))

  (define ~check-srfi-143-77
    (check #t (fxbit-set? 10000 -1)))

  (define ~check-srfi-143-78
    (check #t (fxbit-set? 1000 -1)))

  (define ~check-srfi-143-79
    (check 0 (fxcopy-bit 0 0 #f)))

  (define ~check-srfi-143-80
    (check -1 (fxcopy-bit 0 -1 #t)))

  (define ~check-srfi-143-81
    (check 1 (fxcopy-bit 0 0 #t)))

  (define ~check-srfi-143-82
    (check #x106 (fxcopy-bit 8 6 #t)))

  (define ~check-srfi-143-83
    (check 6 (fxcopy-bit 8 6 #f)))

  (define ~check-srfi-143-84
    (check -2 (fxcopy-bit 0 -1 #f)))

  (define ~check-srfi-143-85
    (check 0 (fxbit-field 6 0 1)))

  (define ~check-srfi-143-86
    (check 3 (fxbit-field 6 1 3)))

  (define ~check-srfi-143-87
    (check 2 (fxarithmetic-shift 1 1)))

  (define ~check-srfi-143-88
    (check 0 (fxarithmetic-shift 1 -1)))

  (define ~check-srfi-143-89
    (check #b110  (fxbit-field-rotate #b110 1 1 2)))

  (define ~check-srfi-143-90
    (check #b1010 (fxbit-field-rotate #b110 1 2 4)))

  (define ~check-srfi-143-91
    (check #b1011 (fxbit-field-rotate #b0111 -1 1 4)))

  (define ~check-srfi-143-92
    (check #b110 (fxbit-field-rotate #b110 0 0 10)))

  (define ~check-srfi-143-93
    (check 6 (fxbit-field-reverse 6 1 3)))

  (define ~check-srfi-143-94
    (check 12 (fxbit-field-reverse 6 1 4)))

  (define ~check-srfi-143-95
    (check -11 (fxnot 10)))

  (define ~check-srfi-143-96
    (check 36 (fxnot -37)))

  (define ~check-srfi-143-97
    (check 11 (fxior 3  10)))

  (define ~check-srfi-143-98
    (check 10 (fxand 11 26)))

  (define ~check-srfi-143-99
    (check 9 (fxxor 3 10)))

  (define ~check-srfi-143-100
    (check 4 (fxand 37 12)))

  (define ~check-srfi-143-101
    (check 32 (fxarithmetic-shift 8 2)))

  (define ~check-srfi-143-102
    (check 4 (fxarithmetic-shift 4 0)))

  (define ~check-srfi-143-103
    (check 4 (fxarithmetic-shift 8 -1)))

  (define ~check-srfi-143-104
    (check 0 (fxlength  0)))

  (define ~check-srfi-143-105
    (check 1 (fxlength  1)))

  (define ~check-srfi-143-106
    (check 0 (fxlength -1)))

  (define ~check-srfi-143-107
    (check 3 (fxlength  7)))

  (define ~check-srfi-143-108
    (check 3 (fxlength -7)))

  (define ~check-srfi-143-109
    (check 4 (fxlength  8)))

  (define ~check-srfi-143-110
    (check 3 (fxlength -8)))

  (define ~check-srfi-143-111
    ;; TODO: investigate
    (check #t (fxbit-set? 3 10)))

  (define ~check-srfi-143-112
    ;; TODO: investigate
    (check #t (fxbit-set? 2 6)))

  (define ~check-srfi-143-113
    (check #f (fxbit-set? 0 6)))

  (define ~check-srfi-143-114
    (check #b100 (fxcopy-bit 2 0 #t)))

  (define ~check-srfi-143-115
    (check #b1011 (fxcopy-bit 2 #b1111 #f)))

  (define ~check-srfi-143-116
    (check 1 (fxfirst-set-bit 2)))

  (define ~check-srfi-143-117
    (check 3 (fxfirst-set-bit 40)))

  (define ~check-srfi-143-118
    (check 2 (fxfirst-set-bit -28)))

  (define ~check-srfi-143-119
    (check 1 (fxand #b1 #b1)))

  (define ~check-srfi-143-120
    (check 0 (fxand #b1 #b10)))

  (define ~check-srfi-143-121
    (check #b10 (fxand #b11 #b10)))

  (define ~check-srfi-143-122
    (check #b101 (fxand #b101 #b111)))

  (define ~check-srfi-143-123
    (check #b111 (fxand -1 #b111)))

  (define ~check-srfi-143-124
    (check #b110 (fxand -2 #b111)))

  (define ~check-srfi-143-125
    (check 1 (fxarithmetic-shift 1 0)))

  (define ~check-srfi-143-126
    (check 4 (fxarithmetic-shift 1 2)))

  (define ~check-srfi-143-127
    (check 8 (fxarithmetic-shift 1 3)))

  (define ~check-srfi-143-128
    (check 16 (fxarithmetic-shift 1 4)))

  (define ~check-srfi-143-129
    (check -1 (fxarithmetic-shift -1 0)))

  (define ~check-srfi-143-130
    (check -2 (fxarithmetic-shift -1 1)))

  (define ~check-srfi-143-131
    (check -4 (fxarithmetic-shift -1 2)))

  (define ~check-srfi-143-132
    (check -8 (fxarithmetic-shift -1 3)))

  (define ~check-srfi-143-133
    (check -16 (fxarithmetic-shift -1 4)))

  (define ~check-srfi-143-134
    (check #b1010 (fxbit-field #b1101101010 0 4)))

  (define ~check-srfi-143-135
    (check #b101101 (fxbit-field #b1101101010 3 9)))

  (define ~check-srfi-143-136
    (check #b10110 (fxbit-field #b1101101010 4 9)))

  (define ~check-srfi-143-137
    (check #b110110 (fxbit-field #b1101101010 4 10)))

  (define ~check-srfi-143-138
    (check 3 (fxif 1 1 2)))

  (define ~check-srfi-143-139
    (check #b00110011 (fxif #b00111100 #b11110000 #b00001111)))

  (define ~check-srfi-143-140
    (check #b1 (fxcopy-bit 0 0 #t))))
