(library (srfi srfi-151-check)

  (export ~check-srfi-151-001 ~check-srfi-151-002 ~check-srfi-151-003 ~check-srfi-151-004 ~check-srfi-151-005 ~check-srfi-151-006
~check-srfi-151-007 ~check-srfi-151-008 ~check-srfi-151-009 ~check-srfi-151-010 ~check-srfi-151-011 ~check-srfi-151-012 ~check-srfi-151-013
~check-srfi-151-014 ~check-srfi-151-015 ~check-srfi-151-016 ~check-srfi-151-017 ~check-srfi-151-018 ~check-srfi-151-019 ~check-srfi-151-020
~check-srfi-151-021 ~check-srfi-151-022 ~check-srfi-151-023 ~check-srfi-151-024 ~check-srfi-151-025 ~check-srfi-151-026 ~check-srfi-151-027
~check-srfi-151-028 ~check-srfi-151-029 ~check-srfi-151-030 ~check-srfi-151-031 ~check-srfi-151-032 ~check-srfi-151-033 ~check-srfi-151-034
~check-srfi-151-035 ~check-srfi-151-036 ~check-srfi-151-037 ~check-srfi-151-038 ~check-srfi-151-039 ~check-srfi-151-040 ~check-srfi-151-041
~check-srfi-151-042 ~check-srfi-151-043 ~check-srfi-151-044 ~check-srfi-151-045 ~check-srfi-151-046 ~check-srfi-151-047 ~check-srfi-151-048
~check-srfi-151-049 ~check-srfi-151-050 ~check-srfi-151-051 ~check-srfi-151-052 ~check-srfi-151-053 ~check-srfi-151-054 ~check-srfi-151-055
~check-srfi-151-056 ~check-srfi-151-057 ~check-srfi-151-058 ~check-srfi-151-059 ~check-srfi-151-060 ~check-srfi-151-061 ~check-srfi-151-062
~check-srfi-151-063 ~check-srfi-151-064 ~check-srfi-151-065 ~check-srfi-151-066 ~check-srfi-151-067 ~check-srfi-151-068 ~check-srfi-151-069
~check-srfi-151-070 ~check-srfi-151-071 ~check-srfi-151-072 ~check-srfi-151-073 ~check-srfi-151-074 ~check-srfi-151-075 ~check-srfi-151-076
~check-srfi-151-077 ~check-srfi-151-078 ~check-srfi-151-079 ~check-srfi-151-080 ~check-srfi-151-081 ~check-srfi-151-082 ~check-srfi-151-083
~check-srfi-151-084 ~check-srfi-151-085 ~check-srfi-151-086 ~check-srfi-151-087 ~check-srfi-151-088 ~check-srfi-151-089 ~check-srfi-151-090
~check-srfi-151-091 ~check-srfi-151-092 ~check-srfi-151-093 ~check-srfi-151-094 ~check-srfi-151-095 ~check-srfi-151-096 ~check-srfi-151-097
~check-srfi-151-098 ~check-srfi-151-099 ~check-srfi-151-100 ~check-srfi-151-101 ~check-srfi-151-102 ~check-srfi-151-103 ~check-srfi-151-104
~check-srfi-151-105 ~check-srfi-151-106 ~check-srfi-151-107 ~check-srfi-151-108 ~check-srfi-151-109 ~check-srfi-151-110 ~check-srfi-151-111
~check-srfi-151-112 ~check-srfi-151-113 ~check-srfi-151-114 ~check-srfi-151-115 ~check-srfi-151-116 ~check-srfi-151-117 ~check-srfi-151-118
~check-srfi-151-119 ~check-srfi-151-120 ~check-srfi-151-121 ~check-srfi-151-122 ~check-srfi-151-123 ~check-srfi-151-124 ~check-srfi-151-125
~check-srfi-151-126 ~check-srfi-151-127 ~check-srfi-151-128 ~check-srfi-151-129 ~check-srfi-151-130 ~check-srfi-151-131 ~check-srfi-151-132
~check-srfi-151-133 ~check-srfi-151-134 ~check-srfi-151-135 ~check-srfi-151-136 ~check-srfi-151-137 ~check-srfi-151-138 ~check-srfi-151-139
~check-srfi-151-140 ~check-srfi-151-141 ~check-srfi-151-142 ~check-srfi-151-143 ~check-srfi-151-144 ~check-srfi-151-145 ~check-srfi-151-146
~check-srfi-151-147 ~check-srfi-151-148 ~check-srfi-151-149 ~check-srfi-151-150 ~check-srfi-151-151 ~check-srfi-151-152 ~check-srfi-151-153
~check-srfi-151-154 ~check-srfi-151-155 ~check-srfi-151-156 ~check-srfi-151-157 ~check-srfi-151-158 ~check-srfi-151-159 ~check-srfi-151-160
~check-srfi-151-161 ~check-srfi-151-162 ~check-srfi-151-163 ~check-srfi-151-164 ~check-srfi-151-165 ~check-srfi-151-166 ~check-srfi-151-167
~check-srfi-151-168 ~check-srfi-151-169 ~check-srfi-151-170 ~check-srfi-151-171 ~check-srfi-151-172 ~check-srfi-151-173 ~check-srfi-151-174
~check-srfi-151-175 ~check-srfi-151-176 ~check-srfi-151-177 ~check-srfi-151-178 ~check-srfi-151-179 ~check-srfi-151-180 ~check-srfi-151-181
~check-srfi-151-182 ~check-srfi-151-183 ~check-srfi-151-184 ~check-srfi-151-185 ~check-srfi-151-186 ~check-srfi-151-187 #;~check-srfi-151-188
~check-srfi-151-189 ~check-srfi-151-190 ~check-srfi-151-191 ~check-srfi-151-192 #;~check-srfi-151-193 ~check-srfi-151-194 ~check-srfi-151-195
~check-srfi-151-196 ~check-srfi-151-197 ~check-srfi-151-198 ~check-srfi-151-199 ~check-srfi-151-200 ~check-srfi-151-201 ~check-srfi-151-202
~check-srfi-151-203 ~check-srfi-151-204 ~check-srfi-151-205 ~check-srfi-151-206 ~check-srfi-151-207 ~check-srfi-151-208 ~check-srfi-151-209
~check-srfi-151-210 ~check-srfi-151-211 ~check-srfi-151-212 ~check-srfi-151-213 ~check-srfi-151-214 ~check-srfi-151-215 ~check-srfi-151-216
~check-srfi-151-217 ~check-srfi-151-218 ~check-srfi-151-219 ~check-srfi-151-220 ~check-srfi-151-221 ~check-srfi-151-222 ~check-srfi-151-223
~check-srfi-151-224 ~check-srfi-151-225 ~check-srfi-151-226 ~check-srfi-151-227 ~check-srfi-151-228 ~check-srfi-151-229 ~check-srfi-151-230
~check-srfi-151-231 ~check-srfi-151-232 ~check-srfi-151-233 ~check-srfi-151-234 ~check-srfi-151-235 ~check-srfi-151-236 ~check-srfi-151-237
~check-srfi-151-238 ~check-srfi-151-239 ~check-srfi-151-240 ~check-srfi-151-241 ~check-srfi-151-242 ~check-srfi-151-243)

  (import (scheme base)
          (letloop check)
          (srfi srfi-151))

  (define ~check-srfi-151-001
    (check -1 (bitwise-not 0)))

  (define ~check-srfi-151-002
    (check 0 (bitwise-not -1)))

  (define ~check-srfi-151-003
    (check -11 (bitwise-not 10)))

  (define ~check-srfi-151-004
    (check 36 (bitwise-not -37)))

  (define ~check-srfi-151-005
    (check 0 (bitwise-and #b0 #b1)))

  (define ~check-srfi-151-006
    (check 1680869008 (bitwise-and -193073517 1689392892)))

  (define ~check-srfi-151-007
    (check 3769478 (bitwise-and 1694076839 -4290775858)))

  (define ~check-srfi-151-008
    (check 6 (bitwise-and 14 6)))

  (define ~check-srfi-151-009
    (check 10 (bitwise-and 11 26)))

  (define ~check-srfi-151-010
    (check 4 (bitwise-and 37 12)))

  (define ~check-srfi-151-011
    (check 1 (bitwise-and #b1 #b1)))

  (define ~check-srfi-151-012
    (check 0 (bitwise-and #b1 #b10)))

  (define ~check-srfi-151-013
    (check #b10 (bitwise-and #b11 #b10)))

  (define ~check-srfi-151-014
    (check #b101 (bitwise-and #b101 #b111)))

  (define ~check-srfi-151-015
    (check #b111 (bitwise-and -1 #b111)))

  (define ~check-srfi-151-016
    (check #b110 (bitwise-and -2 #b111)))

  (define ~check-srfi-151-017
    (check 3769478 (bitwise-and -4290775858 1694076839)))

  (define ~check-srfi-151-018
    (check -4294967295 (bitwise-ior 1 (- -1 #xffffffff))))

  (define ~check-srfi-151-019
    (check -18446744073709551615 (bitwise-ior 1 (- -1 #xffffffffffffffff))))

  (define ~check-srfi-151-020
    (check 14 (bitwise-ior 10 12)))

  (define ~check-srfi-151-021
    (check 11 (bitwise-ior 3  10)))

  (define ~check-srfi-151-022
    (check -4294967126 (bitwise-xor #b10101010 (- -1 #xffffffff))))

  (define ~check-srfi-151-023
    (check -18446744073709551446 (bitwise-xor #b10101010 (- -1 #xffffffffffffffff))))

  (define ~check-srfi-151-024
    (check -2600468497 (bitwise-ior 1694076839 -4290775858)))

  (define ~check-srfi-151-025
    (check -184549633 (bitwise-ior -193073517 1689392892)))

  (define ~check-srfi-151-026
    (check -2604237975 (bitwise-xor 1694076839 -4290775858)))

  (define ~check-srfi-151-027
    (check -1865418641 (bitwise-xor -193073517 1689392892)))

  (define ~check-srfi-151-028
    (check 6 (bitwise-xor 10 12)))

  (define ~check-srfi-151-029
    (check 9 (bitwise-xor 3 10)))

  (define ~check-srfi-151-030
    (check (bitwise-not -4294967126) (bitwise-eqv #b10101010 (- -1 #xffffffff))))

  (define ~check-srfi-151-031
    (check -42 (bitwise-eqv 37 12)))

  (define ~check-srfi-151-032
    (check -1 (bitwise-nand 0 0)))

  (define ~check-srfi-151-033
    (check -1 (bitwise-nand 0 -1)))

  (define ~check-srfi-151-034
    (check -124 (bitwise-nand -1 123)))

  (define ~check-srfi-151-035
    (check -11 (bitwise-nand 11 26)))

  (define ~check-srfi-151-036
    (check -28 (bitwise-nor  11 26)))

  (define ~check-srfi-151-037
    (check 0 (bitwise-nor -1 123)))

  (define ~check-srfi-151-038
    (check 16 (bitwise-andc1 11 26)))

  (define ~check-srfi-151-039
    (check 1 (bitwise-andc2 11 26)))

  (define ~check-srfi-151-040
    (check -2 (bitwise-orc1 11 26)))

  (define ~check-srfi-151-041
    (check -1 (bitwise-nor 0 0)))

  (define ~check-srfi-151-042
    (check 0 (bitwise-nor 0 -1)))

  (define ~check-srfi-151-043
    (check 0 (bitwise-andc1 0 0)))

  (define ~check-srfi-151-044
    (check -1 (bitwise-andc1 0 -1)))

  (define ~check-srfi-151-045
    (check 123 (bitwise-andc1 0 123)))

  (define ~check-srfi-151-046
    (check 0 (bitwise-andc2 0 0)))

  (define ~check-srfi-151-047
    (check -1 (bitwise-andc2 -1 0)))

  (define ~check-srfi-151-048
    (check -1 (bitwise-orc1 0 0)))

  (define ~check-srfi-151-049
    (check -1 (bitwise-orc1 0 -1)))

  (define ~check-srfi-151-050
    (check 0 (bitwise-orc1 -1 0)))

  (define ~check-srfi-151-051
    (check -124 (bitwise-orc1 123 0)))

  (define ~check-srfi-151-052
    (check -1 (bitwise-orc2 0 0)))

  (define ~check-srfi-151-053
    (check -1 (bitwise-orc2 -1 0)))

  (define ~check-srfi-151-054
    (check 0 (bitwise-orc2 0 -1)))

  (define ~check-srfi-151-055
    (check -124 (bitwise-orc2 0 123)))

  ;; bitwise/integer

  (define ~check-srfi-151-056
    (check #x1000000000000000100000000000000000000000000000000
          (arithmetic-shift #x100000000000000010000000000000000 64)))

  (define ~check-srfi-151-057
    (check #x8e73b0f7da0e6452c810f32b809079e5
          (arithmetic-shift #x8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b -64)))

  (define ~check-srfi-151-058
    (check 2 (arithmetic-shift 1 1)))

  (define ~check-srfi-151-059
    (check 0 (arithmetic-shift 1 -1)))

  (define ~check-srfi-151-060
    (check 1 (arithmetic-shift 1 0)))

  (define ~check-srfi-151-061
    (check 4 (arithmetic-shift 1 2)))

  (define ~check-srfi-151-062
    (check 8 (arithmetic-shift 1 3)))

  (define ~check-srfi-151-063
    (check 16 (arithmetic-shift 1 4)))

  (define ~check-srfi-151-064
    (check (expt 2 31) (arithmetic-shift 1 31)))

  (define ~check-srfi-151-065
    (check (expt 2 32) (arithmetic-shift 1 32)))

  (define ~check-srfi-151-066
    (check (expt 2 33) (arithmetic-shift 1 33)))

  (define ~check-srfi-151-067
    (check (expt 2 63) (arithmetic-shift 1 63)))

  (define ~check-srfi-151-068
    (check (expt 2 64) (arithmetic-shift 1 64)))

  (define ~check-srfi-151-069
    (check (expt 2 65) (arithmetic-shift 1 65)))

  (define ~check-srfi-151-070
    (check (expt 2 127) (arithmetic-shift 1 127)))

  (define ~check-srfi-151-071
    (check (expt 2 128) (arithmetic-shift 1 128)))

  (define ~check-srfi-151-072
    (check (expt 2 129) (arithmetic-shift 1 129)))

  (define ~check-srfi-151-073
    (check 3028397001194014464 (arithmetic-shift 11829675785914119 8)))

  (define ~check-srfi-151-074
    (check -1 (arithmetic-shift -1 0)))

  (define ~check-srfi-151-075
    (check -2 (arithmetic-shift -1 1)))

  (define ~check-srfi-151-076
    (check -4 (arithmetic-shift -1 2)))

  (define ~check-srfi-151-077
    (check -8 (arithmetic-shift -1 3)))

  (define ~check-srfi-151-078
    (check -16 (arithmetic-shift -1 4)))

  (define ~check-srfi-151-079
    (check (- (expt 2 31)) (arithmetic-shift -1 31)))

  (define ~check-srfi-151-080
    (check (- (expt 2 32)) (arithmetic-shift -1 32)))

  (define ~check-srfi-151-081
    (check (- (expt 2 33)) (arithmetic-shift -1 33)))

  (define ~check-srfi-151-082
    (check (- (expt 2 63)) (arithmetic-shift -1 63)))

  (define ~check-srfi-151-083
    (check (- (expt 2 64)) (arithmetic-shift -1 64)))

  (define ~check-srfi-151-084
    (check (- (expt 2 65)) (arithmetic-shift -1 65)))

  (define ~check-srfi-151-085
    (check (- (expt 2 127)) (arithmetic-shift -1 127)))

  (define ~check-srfi-151-086
    (check (- (expt 2 128)) (arithmetic-shift -1 128)))

  (define ~check-srfi-151-087
    (check (- (expt 2 129)) (arithmetic-shift -1 129)))

  (define ~check-srfi-151-088
    (check 0 (arithmetic-shift 1 -63)))

  (define ~check-srfi-151-089
    (check 0 (arithmetic-shift 1 -64)))

  (define ~check-srfi-151-090
    (check 0 (arithmetic-shift 1 -65)))

  (define ~check-srfi-151-091
    (check 32 (arithmetic-shift 8 2)))

  (define ~check-srfi-151-092
    (check 4 (arithmetic-shift 4 0)))

  (define ~check-srfi-151-093
    (check 4 (arithmetic-shift 8 -1)))

  (define ~check-srfi-151-094
    (check -79 (arithmetic-shift -100000000000000000000000000000000 -100)))

  (define ~check-srfi-151-095
    (check 2 (bit-count 12)))

  (define ~check-srfi-151-096
    (check 0 (integer-length  0)))

  (define ~check-srfi-151-097
    (check 1 (integer-length  1)))

  (define ~check-srfi-151-098
    (check 0 (integer-length -1)))

  (define ~check-srfi-151-099
    (check 3 (integer-length  7)))

  (define ~check-srfi-151-100
    (check 3 (integer-length -7)))

  (define ~check-srfi-151-101
    (check 4 (integer-length  8)))

  (define ~check-srfi-151-102
    (check 3 (integer-length -8)))

  (define ~check-srfi-151-103
    (check 9 (bitwise-if 3 1 8)))

  (define ~check-srfi-151-104
    (check 0 (bitwise-if 3 8 1)))

  (define ~check-srfi-151-105
    (check 3 (bitwise-if 1 1 2)))

  (define ~check-srfi-151-106
    (check #b00110011 (bitwise-if #b00111100 #b11110000 #b00001111)))

  ;; bitwise/single

  (define ~check-srfi-151-107
    (check #t (bit-set? 0 1)))

  (define ~check-srfi-151-108
    (check #f (bit-set? 1 1)))

  (define ~check-srfi-151-109
    (check #f (bit-set? 1 8)))

  (define ~check-srfi-151-110
    (check #t (bit-set? 10000 -1)))

  (define ~check-srfi-151-111
    (check #t (bit-set? 1000 -1)))

  (define ~check-srfi-151-112
    (check #t (bit-set? 64 #x10000000000000000)))

  (define ~check-srfi-151-113
    (check #f (bit-set? 64 1)))

  (define ~check-srfi-151-114
    (check #t (bit-set? 3 10)))

  (define ~check-srfi-151-115
    (check #t (bit-set? 2 6)))

  (define ~check-srfi-151-116
    (check #f (bit-set? 0 6)))

  (define ~check-srfi-151-117
    (check 0 (copy-bit 0 0 #f)))

  (define ~check-srfi-151-118
    (check 0 (copy-bit 30 0 #f)))

  (define ~check-srfi-151-119
    (check 0 (copy-bit 31 0 #f)))

  (define ~check-srfi-151-120
    (check 0 (copy-bit 62 0 #f)))

  (define ~check-srfi-151-121
    (check 0 (copy-bit 63 0 #f)))

  (define ~check-srfi-151-122
    (check 0 (copy-bit 128 0 #f)))

  (define ~check-srfi-151-123
    (check -1 (copy-bit 0 -1 #t)))

  (define ~check-srfi-151-124
    (check -1 (copy-bit 30 -1 #t)))

  (define ~check-srfi-151-125
    (check -1 (copy-bit 31 -1 #t)))

  (define ~check-srfi-151-126
    (check -1 (copy-bit 62 -1 #t)))

  (define ~check-srfi-151-127
    (check -1 (copy-bit 63 -1 #t)))

  (define ~check-srfi-151-128
    (check -1 (copy-bit 128 -1 #t)))

  (define ~check-srfi-151-129
    (check 1 (copy-bit 0 0 #t)))

  (define ~check-srfi-151-130
    (check #x106 (copy-bit 8 6 #t)))

  (define ~check-srfi-151-131
    (check 6 (copy-bit 8 6 #f)))

  (define ~check-srfi-151-132
    (check -2 (copy-bit 0 -1 #f)))

  (define ~check-srfi-151-133
    (check 0 (copy-bit 128 #x100000000000000000000000000000000 #f)))

  (define ~check-srfi-151-134
    (check #x100000000000000000000000000000000
	  (copy-bit 128 #x100000000000000000000000000000000 #t)))

  (define ~check-srfi-151-135
    (check #x100000000000000000000000000000000
	  (copy-bit 64 #x100000000000000000000000000000000 #f)))

  (define ~check-srfi-151-136
    (check #x-100000000000000000000000000000000
	  (copy-bit 64 #x-100000000000000000000000000000000 #f)))

  (define ~check-srfi-151-137
    (check #x-100000000000000000000000000000000
	  (copy-bit 256 #x-100000000000000000000000000000000 #t)))

  (define ~check-srfi-151-138
    (check #b100 (copy-bit 2 0 #t)))

  (define ~check-srfi-151-139
    (check #b1011 (copy-bit 2 #b1111 #f)))

  (define ~check-srfi-151-140
    (check #b1 (copy-bit 0 0 #t)))

  (define ~check-srfi-151-141
    (check #b1011 (bit-swap 1 2 #b1101)))

  (define ~check-srfi-151-142
    (check #b1011 (bit-swap 2 1 #b1101)))

  (define ~check-srfi-151-143
    (check #b1110 (bit-swap 0 1 #b1101)))

  (define ~check-srfi-151-144
    (check #b10000000101 (bit-swap 3 10 #b1101)))

  (define ~check-srfi-151-145
    (check 1 (bit-swap 0 2 4)))

  (define ~check-srfi-151-146
    (check #t (any-bit-set? 3 6)))

  (define ~check-srfi-151-147
    (check #f (any-bit-set? 3 12)))

  (define ~check-srfi-151-148
    (check #t (every-bit-set? 4 6)))

  (define ~check-srfi-151-149
    (check #f (every-bit-set? 7 6)))

  (define ~check-srfi-151-150
    (check -1 (first-set-bit 0)))

  (define ~check-srfi-151-151
    (check 0 (first-set-bit 1)))

  (define ~check-srfi-151-152
    (check 0 (first-set-bit 3)))

  (define ~check-srfi-151-153
    (check 2 (first-set-bit 4)))

  (define ~check-srfi-151-154
    (check 1 (first-set-bit 6)))

  (define ~check-srfi-151-155
    (check 0 (first-set-bit -1)))

  (define ~check-srfi-151-156
    (check 1 (first-set-bit -2)))

  (define ~check-srfi-151-157
    (check 0 (first-set-bit -3)))

  (define ~check-srfi-151-158
    (check 2 (first-set-bit -4)))

  (define ~check-srfi-151-159
    (check 128 (first-set-bit #x100000000000000000000000000000000)))

  (define ~check-srfi-151-160
    (check 1 (first-set-bit 2)))

  (define ~check-srfi-151-161
    (check 3 (first-set-bit 40)))

  (define ~check-srfi-151-162
    (check 2 (first-set-bit -28)))

  (define ~check-srfi-151-163
    (check 99 (first-set-bit (expt  2 99))))

  (define ~check-srfi-151-164
    (check 99 (first-set-bit (expt -2 99))))

  ;; bitwise/field

  (define ~check-srfi-151-165
    (check 0 (bit-field 6 0 1)))

  (define ~check-srfi-151-166
    (check 3 (bit-field 6 1 3)))

  (define ~check-srfi-151-167
    (check 1 (bit-field 6 2 999)))

  (define ~check-srfi-151-168
    (check 1 (bit-field #x100000000000000000000000000000000 128 129)))

  (define ~check-srfi-151-169
    (check #b1010 (bit-field #b1101101010 0 4)))

  (define ~check-srfi-151-170
    (check #b101101 (bit-field #b1101101010 3 9)))

  (define ~check-srfi-151-171
    (check #b10110 (bit-field #b1101101010 4 9)))

  (define ~check-srfi-151-172
    (check #b110110 (bit-field #b1101101010 4 10)))

  (define ~check-srfi-151-173
    (check #t (bit-field-any? #b101101 0 2)))

  (define ~check-srfi-151-174
    (check #t (bit-field-any? #b101101 2 4)))

  (define ~check-srfi-151-175
    (check #f (bit-field-any? #b101101 1 2)))

  (define ~check-srfi-151-176
    (check #f (bit-field-every? #b101101 0 2)))

  (define ~check-srfi-151-177
    (check #t (bit-field-every? #b101101 2 4)))

  (define ~check-srfi-151-178
    (check #t (bit-field-every? #b101101 0 1)))

  (define ~check-srfi-151-179
    (check #b100000 (bit-field-clear #b101010 1 4)))

  (define ~check-srfi-151-180
    (check #b101110 (bit-field-set #b101010 1 4)))

  (define ~check-srfi-151-181
    (check #b111 (bit-field-replace #b110 1 0 1)))

  (define ~check-srfi-151-182
    (check #b110 (bit-field-replace #b110 1 1 2)))

  (define ~check-srfi-151-183
    (check #b010 (bit-field-replace #b110 1 1 3)))

  (define ~check-srfi-151-184
    (check #b100100 (bit-field-replace #b101010 #b010 1 4)))

  (define ~check-srfi-151-185
    (check #b1001 (bit-field-replace-same #b1111 #b0000 1 3)))

  (define ~check-srfi-151-186
    (check #b110  (bit-field-rotate #b110 1 1 2)))

  (define ~check-srfi-151-187
    (check #b1010 (bit-field-rotate #b110 1 2 4)))

  ;; TODO: FIXME: negative rotation is invalid according to chez
  (define ~check-srfi-151-188
    (check #b1011 (bit-field-rotate #b0111 -1 1 4)))

  (define ~check-srfi-151-189
    (check #b0  (bit-field-rotate #b0 128 0 256)))

  (define ~check-srfi-151-190
    (check #b1  (bit-field-rotate #b1 128 1 256)))

  (define ~check-srfi-151-191
    (check #x100000000000000000000000000000000
	  (bit-field-rotate #x100000000000000000000000000000000 128 0 64)))

  (define ~check-srfi-151-192
    (check #x100000000000000000000000000000008
	  (bit-field-rotate #x100000000000000000000000000000001 3 0 64)))

  ;; TODO: FIXME: negative rotation is invalid according to chez
  (define ~check-srfi-151-193
   (check #x100000000000000002000000000000000
         (bit-field-rotate #x100000000000000000000000000000001 -3 0 64)))

  (define ~check-srfi-151-194
    (check #b110 (bit-field-rotate #b110 0 0 10)))

  (define ~check-srfi-151-195
    (check #b110 (bit-field-rotate #b110 0 0 256)))

  (define ~check-srfi-151-196
    (check 1 (bit-field-rotate #x100000000000000000000000000000000 1 0 129)))

  (define ~check-srfi-151-197
    (check 6 (bit-field-reverse 6 1 3)))

  (define ~check-srfi-151-198
    (check 12 (bit-field-reverse 6 1 4)))

  (define ~check-srfi-151-199
    (check #x80000000 (bit-field-reverse 1 0 32)))

  (define ~check-srfi-151-200
    (check #x40000000 (bit-field-reverse 1 0 31)))

  (define ~check-srfi-151-201
    (check #x20000000 (bit-field-reverse 1 0 30)))

  (define ~check-srfi-151-202
    (check (bitwise-ior (arithmetic-shift -1 32) #xFBFFFFFF)
	  (bit-field-reverse -2 0 27)))

  (define ~check-srfi-151-203
    (check (bitwise-ior (arithmetic-shift -1 32) #xF7FFFFFF)
	  (bit-field-reverse -2 0 28)))

  (define ~check-srfi-151-204
    (check (bitwise-ior (arithmetic-shift -1 32) #xEFFFFFFF)
	  (bit-field-reverse -2 0 29)))

  (define ~check-srfi-151-205
    (check (bitwise-ior (arithmetic-shift -1 32) #xDFFFFFFF)
	  (bit-field-reverse -2 0 30)))

  (define ~check-srfi-151-206
    (check (bitwise-ior (arithmetic-shift -1 32) #xBFFFFFFF)
	  (bit-field-reverse -2 0 31)))

  (define ~check-srfi-151-207
    (check (bitwise-ior (arithmetic-shift -1 32) #x7FFFFFFF)
	  (bit-field-reverse -2 0 32)))

  (define ~check-srfi-151-208
    (check 5 (bit-field-reverse #x140000000000000000000000000000000 0 129)))

  ;; bitwise/conversion

  (define ~check-srfi-151-209
    (check '(#t #f #t #f #t #t #t) (bits->list #b1110101)))

  (define ~check-srfi-151-210
    (check '(#f #t #f #t) (bits->list #b111010 4)))

  (define ~check-srfi-151-211
    (check #b1110101 (list->bits '(#t #f #t #f #t #t #t))))

  (define ~check-srfi-151-212
    (check #b111010100 (list->bits '(#f #f #t #f #t #f #t #t #t))))

  (define ~check-srfi-151-213
    (check '(#t #t) (bits->list 3)))

  (define ~check-srfi-151-214
    (check '(#f #t #t #f) (bits->list 6 4)))

  (define ~check-srfi-151-215
    (check '(#f #t) (bits->list 6 2)))

  (define ~check-srfi-151-216
    (check '(#t #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	       #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f)
	  (bits->list 1 128)))

  (define ~check-srfi-151-217
    (check '(#f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	    #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #t)
	  (bits->list #x100000000000000000000000000000000)))

  (define ~check-srfi-151-218
    (check 6 (list->bits '(#f #t #t))))

  (define ~check-srfi-151-219
    (check 12 (list->bits '(#f #f #t #t))))

  (define ~check-srfi-151-220
    (check 6 (list->bits '(#f #t #t #f))))

  (define ~check-srfi-151-221
    (check 2 (list->bits '(#f #t))))

  (define ~check-srfi-151-222
    (check 1 (list->bits
	     '(#t #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
		  #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f))))

  (define ~check-srfi-151-223
    (check #x100000000000000000000000000000000
	  (list->bits
	   '(#f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
	     #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #t))))

  (define ~check-srfi-151-224
    (check #x03FFFFFF (list->bits '(#t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-225
    (check #x07FFFFFF (list->bits '(#t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-226
    (check #x0FFFFFFF (list->bits '(#t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-227
    (check #x1FFFFFFF (list->bits '(#t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-228
    (check #x3FFFFFFF (list->bits '(#t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-229
    (check #x7FFFFFFF (list->bits '(#t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))
  (define ~check-srfi-151-230
    (check #xFFFFFFFF (list->bits '(#t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t
				      #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-231
    (check #x1FFFFFFFF (list->bits '(#t
				    #t #t #t #t #t #t #t #t
				    #t #t #t #t #t #t #t #t
				    #t #t #t #t #t #t #t #t
				    #t #t #t #t #t #t #t #t))))

  (define ~check-srfi-151-232
    (check 1 (list->bits '(#t #f))))

  (define ~check-srfi-151-233
    (check #b1110101 (vector->bits '#(#t #f #t #f #t #t #t))))

  (define ~check-srfi-151-234
    (check #b00011010100 (vector->bits '#(#f #f #t #f #t #f #t #t))))

  (define ~check-srfi-151-235
    (check '#(#t #t #t #f #t #f #t #f #f) (bits->vector #b1010111 9)))

  (define ~check-srfi-151-236
    (check '#(#t #t #t #f #t #f #t #f #f) (bits->vector #b1010111 9)))

  (define ~check-srfi-151-237
    (check #b1110101 (bits #t #f #t #f #t #t #t)))

  (define ~check-srfi-151-238
    (check 0 (bits)))

  (define ~check-srfi-151-239
    (check #b111010100 (bits #f #f #t #f #t #f #t #t #t)))

  ;; bitwise/fold

  (define ~check-srfi-151-240
    (check '(#t #f #t #f #t #t #t) (bitwise-fold cons '() #b1010111)))

  (define ~check-srfi-151-241
    (check 5
          (let ((count 0))
            (bitwise-for-each (lambda (b) (if b (set! count (+ count 1))))
                              #b1010111)
            count)))

  (define ~check-srfi-151-242
    (check #b101010101
          (bitwise-unfold (lambda (i) (= i 10)) even? (lambda (i) (+ i 1)) 0)))

  (define ~check-srfi-151-243
    (check #t
          (let ((g (make-bitwise-generator #b110)))
            (and
             (equal? #f (g))
             (equal? #t (g))
             (equal? #t (g))
             (equal? #f (g)))))))
