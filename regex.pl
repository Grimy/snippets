#!/bin/perl -wl

# One Regex to rule them all, One Regex to find them,
# One Regex to match them all and in the darkness bind them

# Known limitations:
# Variable-length lookbehinds
# References to non-existent groups
# Invalid ranges
# (?x)

# Contrary to what is documented, (*COMMIT) and (*ACCEPT) can take an argument
# Contrary to what is documented, the p flag can appear after a -, as in (?-p)
# The undocumented (?c), (?g) and (?o) are ignored instead of erroring out
# /(?(/ crashes in 5.20 only (panic: memory wrap)
# /(?[\ &!])/ crashes in 5.22 only (segfault)
# /(?[\c#])/, /(?[\c[])/ /(?[\c]])/ and /(?[\c\])/ are (incorrectly?) rejected
# /\p /, /\P /, /\p^/ and /\P^/ give strange warnings
# The optimizer interacts strangely with some diagnostics (/a|\P!/ vs. /\P!|a/)
# \N{} is ignored inside interpolated variables, but otherwise fatal
# \o{} and \x{} have inconsistent behavior
# /(?[(\c])/ is somehow accepted, but not /(?[\c]])/

use strict;
use warnings;
no warnings qw(qw);

$|--;
$" = '|';
my @ascii = map chr, 32..127;
my $v = int($] * 1000 - 5000);

# Before 5.23, \C was accepted
my $C = $v >= 23 ? 'C' : '';

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

# Since 5.20, nested quantifiers are sometimes accepted.
my $nested = $v == 23 ? '[?]' : $v == 22 ? '[?+]' : $v >= 20 ? '[?]' : '(?!)';

# In 5.18 only, \8 is accepted under weird conditions
# Trying to emulate this bug yields a SEGFAULT
# my $wtf = $v == 18 ? qr/(?:(?<!(?<!\\)[.^$)])(?<!\\[ABCDGHKNRSVWXZbdhsvwz])(?:\\[89])*(*ACCEPT))?/ : '';

# Since 5.18, {m,n} with m > n is accepted
my @longer = map "\\d{$_}\\d+,0*\\d{$_}}", 1..4;
my @same = map "\\d{$_},0*\\d{$_}}", 1..5;
my @digits = map "$_\\d*,0*\\g-1[0-${\--$_}]", 1..9;
my $lt = $v >= 18 ? '' : qr/(?! @longer | (?=@same) (\d*) (?:@digits))/x;

# Since 5.18, flagsets without ) are accepted at the end of a regex (e.g. /(?^/)
my $fend = $v >= 18 ? '(?(?=\z)(?<!\?)(*ACCEPT))' : '';

# Before 5.18, extended character classes (?[…]) didn’t exist
my $exclass = $v >= 18 ? '(?&exclass)' : '(?!)';

# Before 5.18, [=\w*=] was an error
my $posix = $v >= 18 ? '' : '\[ ([=.]) \w* \g-1 \] (*PRUNE) (*FAIL) |';

# Before 5.18, /(?&)/, /(?P>)/, /(?(<>))/, /(?(''))/, and /(?(R&))/ were accepted

# Before 5.16, invalid unicode properties were accepted (e.g. /\p!/)
my $prop = $v >= 16 ? '(?!)' : '(?:{(*PRUNE)[^}]+}|.)';

my $regex = qr/
	\A (?<regex> (?&branch) | \| )* \z (*ACCEPT)
	(?<atom>
		  $posix (?!$quant) [^\\|[()]
		| \\ (?: (?&escape) | [^gk$C] )
		| (?&class)
		| \( \? \[ $exclass \] \)
		| \( (?<look> \? <? [=!] (?&regex)*) \)
		| \( \? \( (?&cond) \) (?&branch)* \|? (?&branch)* \)
		| \( \? (?: [+-]?[1-9]\d* | [0R] | (?:P=|P>|&)(?&name) ) \)
		| \( (?: \? (?: [|>] | '(?&name)' | (?&flag)*: | P?<(?&name)>) )? (?&regex)* \)
		| \( \* (?: (?:MARK)? :[^)]+ | F(?:AIL)? :? ) \)
		| \( \* (?:PRUNE|SKIP|THEN|COMMIT|ACCEPT) (?::[^)]*)? \)
	)
	(?<escape>
		  N (?=(?&quant))
		| g(?=-?\d*[1-9])
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
		| x [[:xdigit:]]{2}
		| [0-7]{3}
		| [DHSVW_adefhnrstvw]
	)
	(?<flag>
		  [$flags]
		| (?<=\?) \^ (?! [a-z]* [d-])
		| a (?= [b-z]* a (?! [b-z]* a))
		| [adlu] (?! [a-z]* [adlu])
		| - (?! [a-z]* [adlu-])
	)
	(?<class>   \[ \^?+ \]?+ (?: \\ (?: (?&escape) | [^N] ) | (?&posx) | [^]\\] )*? \] )
	(?<exclass> [!\s]* (?: (?&posx) | (?&class) | \\ (?: (?&escape) (?<!\\B) | \W ) | \((?&exclass)\)) \s* (?:[-+&|^] \s* (?&exclass))? )
	(?<posx>    \[ ([:=.]) (?= .* (?<!(?=\g-1)(?<!\[).) \g-1] ) (*PRUNE) (?<=:) \^? (?&posix) :] )
	(?<posix>   alpha|alnum|ascii|blank|cntrl|x?digit|graph|lower|print|punct|space|upper|word )
	(?<cond>    (?&look) | DEFINE | R | R&(?&name) | R?[1-9]\d* | '(?&name)' | <(?&name)> )
	(?<name>    (*PRUNE) [_A-Za-z] \w* )
	(?<quant>   [*+?] | {(?=\d++,?\d*}) (*PRUNE) $zero $lt ((?&short)) (?: (?:,$zero\g{-1})? } $nested | ,? (?&short)? } ) )
	(?<short>   (?! [4-9]\d{4} | 3[3-9]\d{3} | 32[89]\d\d | 327[7-9]\d | 3276[7-9] ) \d* )
	(?<comment> \( \? \# [^)]* \) )
	(?<branch>  \( \? (?&flag)* $fend \) | (?&comment) | (?&atom) (?&comment)* (?:(?&quant)[+?]?)?+ (?!(?&quant)) )
/xs;

sub test {
	return if $_ =~ /\Q(?[\N{}])/;
	return if /\(\?\[\s*\(\s*\)\s*\]\)/;
	eval {no warnings; qr/$_/};
	my $me = !!/$regex/;
	my $perl = $@ !~ /^(?!Reference to nonexistent )./;
	print "False positive /$_/: $@" if $me and !$perl;
	print "False negative /$_/ (" . (s/./ord($&)."."/reg) . ")" if !$me and $perl;
}

# ("()"x79 . "\\80")x($] != 5.018004);
# "()"x80 . "\\80";
# qw((?<=a*) (?<=\b*) ()\\1 (())\\2 ()()\\1 (?=()|())\\2);

sub testall {
	my $n = shift() - 1;
	my $prefix = shift;
	my $suffix = shift;
	if ($n) {
		testall($n, "$prefix$_", $suffix, @_) for @_;
	}
	test for map "$prefix$_$suffix", @_;
}

test for
	$regex, '\p^ ', '\N{LATIN SMALL LETTER A}', '[\N{LATIN SMALL LETTER A}]',
	'(?[[ ]])',
	map("\\" . chr, 0..31, 128..255),
	map("\\c" . chr, 0..255),
	map("[\\$_]", @ascii),
	map({$a = "\\$_"; map {"$a$_"} qw({ {} } {!} 0 01 6 -0 +0 -1 {-1} {0} {9} {99999} {FFFFFF})} "a", "b", "d".."z", "A".."Z"),
	map(("[=$_=]", "[=^$_=]", "[:$_:]", "[:^$_:]", "[.$_.]", "[.^$_.]"), qw(A z 0 1 9 ! ^ = : . [ ])),
	map(split(' ', "[$_] [$_$_] [$_!$_] [[$_] [[$_$_] [[$_]] [[$_$_]] [1[$_$_]] [[2$_$_]] [[$_]$_]] [[$_$_$_]] [[$_$_$_$_]] [[$_\[$_$_]] [[$_]$_$_]] (?[[$_$_]])"), qw(: = .)),
	map(("(?[[:$_:]])", "[[:$_:]]", "[[:^$_:]]"), qw(alpha alnum ascii blank cntrl digit graph lower print punct space upper word xdigit invalid)),
	qw~
	!{1,0}?? !{1,1}?? !{1,2}??
	!{01,1}?? !{1,01}?? !{10,100}??
	\80 \99 ()\2 (?|()|())\2 \07 \10 \19 \42 \79 0\c !\c
	\000 \100 \777 \789 \800
	\p1 \p^ $\p* |\P{ |\P} $\p{ !\p* _\Pt \p)
	\xf \xF \xx \x{Invalid)\}++
	\g<> \g'' \g<a> \g'zzz' \gg \g{1}*+
	\k<> \k'' \k<a> \k'zzz' \kk \k{1}*+ \N**
	.\8 !\8 8\8? 8\8{8} 8\8{88888} 8\8{} .{8}\8 {\8 \A\8 \E\8 \|\8 (\8) ()\8
	^.^ $$..^^ a|b ^|$ ||.|| a(b|c)d [a] [a][]
	[\N] [\n] [\P] [\p] [\c] [\o] [\1] [\9] [\80] [\g] [\k] [\N{}] [\N{!}]
	(*) [*] (+) [+] (?) [?]
	({) [{] (}) [}]
	a+++ a*b+cd?e
	{a,a} .{} .{,} .{,1} .{1,1,} .{3,0} .{a,a} .{,,}
	.{0} .{00} .{01} .{0032766} .{032767} .{1,32766} .{1,32767}
	{32767} {32767, .{32767 {32767,32767,32767}
	.{32766} .{32767} .{32770} .{32800} .{33000} .{40000}
	a** a*+ a*? a+* a++ a+? a?* a?+ a??
	a{1}* a{1}+ a{1}? a{,1}* a{1,}*
	(?P=_) (?P>_) (?P<_>) (?P'_') (?'_>) (?<_') (?<_>) (?'A') (?<7>)
	(?P=_/) (?P>_/) (?&_/)
	(?=)* (?!)(?#)+ (?)(?!)? (?<!?)
	(?i-i) (?a)+ (?a){1} (?a:)+ a(?a)* (?^:)? (?adlupimsx)
	(?aaa) (?ada) (?aia) (?iii) (?a-a)
	(?^ (?- (?c (?-p (?6 (?R (?P
	(?# (?#)* a(?#)* a(?#)(?#)+ a(?)(?#)+ ((?#)) (?#()) [(?#])]
	(*PRUNE) (*SKIP) (*MARK) (*THEN) (*COMMIT) (*F) (*FAIL) (*ACCEPT) (*LOL)
	(*PRUNE:) (*SKIP:) (*MARK:) (*THEN:) (*COMMIT:) (*F:) (*FAIL:) (*ACCEPT:)
	(*PRUNE:a) (*SKIP:a) (*MARK:a) (*THEN:a) (*COMMIT:a) (*F:a) (*FAIL:a) (*ACCEPT:a)
	(*:) (*:1) (*:_) (*:a) (*:!) (*:() (*:)) (*:_)*+
	(?{ (?{{}}) (?<=^*) (?<=$*)
	(?( (?(0)) (?(1)) (?(01)) (?(42)) (?(-1)) (?(?|))
	(?(R)) (?(?=)) (?(?!)) (?(?<=)) (?(?<!)) (?(R&D))
	(?(<_>)) (?(P<_>)/) (?('_'))
	(?(<>)) (?('')) (?(R&)) (?P<>)
	(?(R)|) (?(R)||) (?(R)(|)|[|]) (?(DEFINE)) (?(R0)) (?(R1))
	[:alpha:] [[:blah:]] [[:alpha] [[:alpha: [[:!:]] [[:]:]
	[[:ascii::]] [[.span-ll.]] [[=e=]]
	[[:].*yadayada: [[:].*yadayada:]
	(?[ (?[a]) (?[\xFF]) (?[\xFG]) (?[[]]) (?[[a]]) (?[[a])
	(?[[a]|[b]]) (?[[a]+[b]]) (?[[a]&[b]]) (?[[a]-[b]]) (?[[a]^[b]])
	(?[[a]|[b]&[c]) (?[[a]|([b]&[c])]) (?[([a]|[b])&[c]])
	(?[[a]?[b]]) (?[[a]![b]]) (?[[a];[b]]) (?[[a]/[b]]) (?[[a]*[b]])
	(?[[a]^![b]]) (?[[a]^&[b]]) (?[[a]&+[b]])
	(?[[[:word:]]]) (?[[:word:]])
	(?[(\c]) (?[[ ]]) (?[\c#]) (?[\c[]) (?[\c\]) (?[\c]])
	(?[[a](?#)]) (?[[a](?#])])
~;

testall 12, "", "", qw(( ));
testall 8, "", "", qw([ ^ ]);
testall 8, "", "", qw({ 1 , });
testall 5, ".", "", qw({1} {1,} {1,1} + * ?);
testall 2, "", "", @ascii;
testall 4, "(?", ")", @ascii;
testall 4, "(?[", "])", @ascii;

print "UNIT DONE";
exit;

for (1..1E7) {
	my $a = '';
	$a .= chr(32 + rand 96) for 1..rand(16);
	test for "$a";
}

# for my $a (@ascii) {
	# for my $b (@ascii) {
		# for my $c (@ascii) {
			# # for ("$a$b$c\\8", "$a$b\\8$c", "$a\\8$b$c", "\\8$a$b$c") {
			# for my $d (@ascii) {
				# test;
			# }
		# }
	# }
# }
