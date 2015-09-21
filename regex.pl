#!/bin/perl -wl

# One Regex to rule them all, One Regex to find them,
# One Regex to match them all and in the darkness bind them

# Known limitations: Variable-length lookbehinds, references to non-existent groups, invalid ranges

# Contrary to what is documented, (*COMMIT) and (*ACCEPT) can take an argument
# Contrary to what is documented, the p flag can appear after a -, as in (?-p)
# The undocumented (?c), (?g) and (?o) are ignored instead of erroring out
# /(?(/ crashes in 5.20 only (panic: memory wrap)
# /\p /, /\P /, /\p^/ and /\P^/ give strange warnings
# The optimizer interacts strangely with some diagnostics (/a|\P!/ vs. /\P!|a/)
# \N{} is ignored inside interpolated variables, but otherwise fatal
# \o{} and \x{} have inconsistent behavior

use strict;
no warnings qw(qw);
$|--;

my $v = int($] * 1000 - 5000);

# Before 5.22, \c at the end of a regex was accepted
# Before 5.22, \c followed by an ASCII control char was accepted
# Before 5.20, \c followed by anything was accepted
my $cend = $v >= 22 ? '[ -~]' : $v >= 20 ? '(?:\z|[\0-\x7F])' : '(?:\z|.)';

# Before 5.22, extra 0s in quantifiers were accepted (e.g. /.{007}/)
my $zero = $v >= 22 ? '(?!0\d)' : '0*+';

# Since 5.22, (?n) is accepted
my $flags = $v >= 22 ? 'cgimnopsx' : 'cgimopsx';

# Since 5.22, a {}-quantifier attached to nothing is accepted (e.g. /{0}/)
my $quant = $v >= 22 ? '[*+?]' : '(?&quant)';

# Before 5.20, \c{, \b{ and \B{ were accepted
my $brace = $v >= 20 ? '(?!{)' : '';

# Since 5.20, nested quantifiers are sometimes accepted. It got worse in 5.22.
my $nested = $v >= 22 ? '[?+]' : $v >= 20 ? '[?]' : '(?!)';

# In 5.18 only, \8 is accepted under weird conditions
# Trying to emulate this bug yields a SEGFAULT
# my $wtf = $v == 18 ? qr/(?:(?<!(?<!\\)[.^$)])(?<!\\[ABCDGHKNRSVWXZbdhsvwz])(?:\\[89])*(*ACCEPT))?/ : '';

# Since 5.18, {m,n} with m > n is accepted

# Since 5.18, flagsets without ) are accepted at the end of a regex (e.g. /(?^/)
my $fend = $] >= 5.018 ? '(?(?=\z)(?<!\?)(*ACCEPT))' : '';

# Before 5.16, invalid unicode properties were accepted (e.g. /\p!/)
my $prop = $] >= 5.016 ? '(*FAIL)' : '(?<=\A..)\W';

my $regex = qr/
	\A (?<regex> (?&branch) | \| )* \z (*ACCEPT)
	(?<atom>
		  (?!$quant) [^\\|[()]
		| \\ (?&escape) (?<!\\[gk])
		| (?&class) (*PRUNE)
		| \( (?<look> \? <? [=!] (?&regex)*) \)
		| \( \? \( (?&cond) \) (?&branch)* \|? (?&branch)* \)
		| \( \? (?: [+-]?\d+ | [0R] | (?:P=|P>|&)(?&name) ) \)
		| \( (?: \? (?: [|>] | '(?&name)' | (?&flag)*: | P?<(?&name)>) )? (?&regex)* \)
		| \( \* (?: (?:MARK)? :[^)]+ | F(?:AIL)? :? ) \)
		| \( \* (?:PRUNE|SKIP|THEN|COMMIT|ACCEPT) (?::[^)]*)? \)
	)
	(?<escape>
		  N (?=(?&quant))
		| g-?\d*[1-9]
		| N\{  (*PRUNE) }
		| g\{  (*PRUNE) (?:-?\d*[1-9]|(?&name))}
		| x\{  (*PRUNE) [^}]*}
		| k\{  (*PRUNE) (?&name)}
		| k<   (*PRUNE) (?&name)>
		| k'   (*PRUNE) (?&name)'
		| o    (*PRUNE) {[^}]+}
		| [Bb] (*PRUNE) $brace
		| [Pp] (*PRUNE) $prop
		| c    (*PRUNE) $brace $cend
		| .
	)
	(?<flag>
		  [$flags]
		| (?<=\?) \^ (?! [a-z]* [d-])
		| a (?= [b-z]* a (?! [b-z]* a))
		| [adlu] (?! [a-z]* [adlu])
		| - (?! [a-z]* [adlu-])
	)
	(?<class>   \[ \^?+ \]?+ (?: \\ (?&escape) (?<!N) | \[: (?=.*:]) (*PRUNE) (?&posix) :] | [^\\] )*? \] )
	(?<posix>   alpha|alnum|ascii|blank|cntrl|x?digit|graph|lower|print|punct|space|upper|word )
	(?<cond>    (?&look) | DEFINE | R | R&(?&name) | R?[1-9]\d* | '(?&name)' | <(?&name)> )
	(?<name>    (*PRUNE) [_A-Za-z] \w* )
	(?<quant>   [*+?] | {(?=\d++,?\d*}) (*PRUNE) $zero ((?&short)) (?: (?:,$zero\g{-1})? } $nested | ,? (?&short)? } ) )
	(?<short>   (?! [4-9]\d{4} | 3[3-9]\d{3} | 32[89]\d\d | 327[7-9]\d | 3276[7-9] ) \d* )
	(?<comment> \( \? \# [^)]* \) )
	(?<branch>  \( \? (?&flag)* $fend \) | (?&comment) | (?&atom) (?&comment)* (?:(?&quant)[+?]?)?+ (?!(?&quant)) )
/xs;

sub test {
	eval {no warnings; qr/$_/};
	my $me = !!/$regex/;
	my $perl = $@ !~ /^(?!Reference to nonexistent )./;
	print "False positive /$_/: $@" if $me and !$perl;
	print "False negative /$_/ (" . (s/./ord($&)."."/reg) . ")" if !$me and $perl;
}

# ("()"x79 . "\\80")x($] != 5.018004);
# "()"x80 . "\\80";
# qw((?<=a*) (?<=\b*) ()\\1 (())\\2 ()()\\1 (?=()|())\\2);

sub combinations {
	my $n = shift() - 1;
	(@_, $n ? map {my $c = $_; map {"$c$_"} @_} combinations($n, @_) : ());
}

test for
	'\p^ ', '\N{LATIN SMALL LETTER A}', '[\N{LATIN SMALL LETTER A}]',
	map("\\" . chr, 0..255),
	map("\\c" . chr, 0..255),
	map(("(?$_)", "(?^$_)", "(?-$_)"), "a".."z"),
	map({$a = "\\$_"; map {"$a$_"} qw({ {} } {!} 0 01 6 -0 +0 -1 {-1} {0} {9} {99999} {FFFFFF})} "a".."z", "A".."Z"),
	combinations(9, qw(( ))),
	combinations(6, qw([ ^ ])),
	combinations(6, qw({ 1 , })),
	map(".$_", combinations(5, qw({1} {1,} {1,1} + * ?))),
	qw~
	!{1,0}?? !{1,1}?? !{1,2}??
	!{01,1}?? !{1,01}?? !{10,100}??
	\80 \99 ()\2 (?|()|())\2 \\ a\ \07 \10 \19 \42 \79 0\c !\c
	\p0 \p1 \p^ $\p* |\P{ |\P} $\p{ !\p* _\Pt \p)
	\x0 \xf \xF \xx
	\g<> \g'' \g<a> \g'zzz' \gg
	\k<> \k'' \k<a> \k'zzz'
	\N**
	.\8 !\8 8\8? 8\8{8} 8\8{88888} 8\8{} .{8}\8 {\8 \A\8 \E\8 \|\8 (\8) ()\8
	. $ ^.^ $$..^^ | a|b ^|$ ||.|| a(b|c)d [a] [a][]
	[\N] [\n] [\P] [\p] [\c] [\o] [\1] [\9] [\80] [\g] [\k] [\N{}] [\N{!}]
	* a* *a ^* $* |* (* )* [* ]* (*) [*]
	+ a+ +a ^+ $+ |+ (+ )+ [+ ]+ (+) [+]
	? a? ?a ^? $? |? (? )? [? ]? (?) [?]
	a{ {a ^{ ${ |{ ({ ){ [{ ]{ ({) [{]
	a} }a ^} $} |} (} )} [} ]} (}) [}]
	a+++ a*b+cd?e .{ .}
	{a,a} .{} .{,} .{,1} .{1,1,} .{3,0} .{a,a} .{,,}
	.{0} .{00} .{01} .{0032766} .{032767} .{1,32766} .{1,32767}
	{32767} {32767, .{32767 {32767,32767,32767}
	.{32766} .{32767} .{32770} .{32800} .{33000} .{40000}
	a** a*+ a*? a+* a++ a+? a?* a?+ a??
	a{1}* a{1}+ a{1}? a{,1}* a{1,}*
	(?=) (?!) (?<) (?<=) (?<!) (?') (?>) (?|)
	(?P=_) (?P>_) (?P<_>) (?P'_') (?'_>) (?<_') (?<_>) (?'A') (?<7>) (?&A) (?&)
	(?P=_/) (?P>_/) (?&_/) (?R/) (?0/)
	(?=)* (?!)(?#)+ (?)(?!)? (?<!?)
	(?-) (?^) (?i-i) (?a)+ (?a){1} (?a:)+ a(?a)* (?^:)? (?adlupimsx)
	(?aa) (?aaa) (?ad) (?da) (?dl) (?ua) (?ada) (?aia) (?iii)
	(?^-) (?a-) (?u-) (?a-a) (?--) (?^^)
	(?^ (?- (?c (?-p (?6 (?R (?P (?6/)
	(?#) (?# (?#)* a(?#)* a(?#)(?#)+ a(?)(?#)+ ((?#)) (?#()) (?a#) [(?#])]
	(*PRUNE) (*SKIP) (*MARK) (*THEN) (*COMMIT) (*F) (*FAIL) (*ACCEPT) (*LOL)
	(*PRUNE:) (*SKIP:) (*MARK:) (*THEN:) (*COMMIT:) (*F:) (*FAIL:) (*ACCEPT:)
	(*PRUNE:a) (*SKIP:a) (*MARK:a) (*THEN:a) (*COMMIT:a) (*F:a) (*FAIL:a) (*ACCEPT:a)
	(*:) (*:1) (*:_) (*:a) (*:!) (*:() (*:)) (*:_)*+
	(?{}) (?{ (?{{}}) (?<=^*) (?<=$*)
	(?0) (?R) (?1) (?-1) (?+1) (?-) (?+) (?7)
	(?( (?() (?()) (?(0)) (?(1)) (?(01)) (?(42)) (?(-1)) (?(?|))
	(?(R)) (?(?=)) (?(?!)) (?(?<=)) (?(?<!)) (?(R&D))
	(?(<_>)) (?(P<_>)/) (?('_'))
	(?(R)|) (?(R)||) (?(R)(|)|[|]) (?(DEFINE)) (?(R0)) (?(R1))
	[[:alpha:]] [[:blah:]] [[:alpha] [[:alpha: [[:!:]] [[:]:]
	[[:!] [[:A] [[:z] [[:1] [[:: [[::]] [[:]] [[::] [[:]
	[[:].*yadayada: [[:].*yadayada:]
~;

print "UNIT DONE";

# my @tokens = ("^", "-", "a".."z");
# for my $a (@tokens) {
	# for my $b (@tokens) {
		# for my $c (@tokens) {
			# for my $d (@tokens) {
				# $_ = "(?$a$b$c$d)";
				# test;
			# }
		# }
	# }
# }

my @tokens = grep {1} map {chr} 32..127;

for (1..1E7) {
	my $a = '';
	$a .= chr(32 + rand 96) for 1..rand(16);
	test for "$a\\";
}

# for my $a (@tokens) {
	# for my $b (@tokens) {
		# for my $c (@tokens) {
			# # for ("$a$b$c\\8", "$a$b\\8$c", "$a\\8$b$c", "\\8$a$b$c") {
			# for my $d (@tokens) {
				# test;
			# }
		# }
	# }
# }
