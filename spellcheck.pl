#!/usr/bin/perl

use strict;
use warnings;
use Text::Levenshtein::XS qw/distance/;
use utf8;
use Term::ANSIColor;
use Term::ReadLine;

sub readLexicon( $ );
sub saveLexicon( $$ );
sub spellCheckSentence( $ );

# TBL is the Romanian lexicon, word TAB lemma TAB MSD format.
# Column corpus is the corpus with lemmas and POS tags, word TAB lemma TAB MSD format (one new line between sentences).
# Word list are new words word TAB lemma TAB MSD format, to be added to TBL.
# Everything is UTF-8, except the TBL.

if ( scalar( @ARGV ) != 1 ) {
	die( "spellcheck.pl medical-selected-[train|test].txt" );
}

binmode( STDOUT, ":utf8" );

################ Config section ####################################
# Set your path correctly to this file!!
my( $TBLFILE ) = "/home/rion/ttlrun/res/ro/tbl.wordform.ro.v81";
my( $ADDTBLFILE ) = "tbl.wordform.ro.medical";
################ End config section ################################

my( $CORPUSFILE ) = $ARGV[0];
my( $cygterm ) = new Term::ReadLine( 'spellcheck' );

$cygterm->enableUTF8();

my( %ROTBL ) = readLexicon( $TBLFILE );
my( %ROEXTBL ) = readLexicon( $ADDTBLFILE );

open( COR, "<", $CORPUSFILE ) or die( "spellcheck::main: cannot open corpus file '$CORPUSFILE' !\n" );
binmode( COR, ":utf8" );
open( COROUT, ">", $CORPUSFILE . ".sav" ) or die( "spellcheck::main: cannot open out corpus file '${CORPUSFILE}.sav' !\n" );
binmode( COROUT, ":utf8" );

my( @currentsent ) = ();
my( $sessionended ) = 0;

while ( my $line = <COR> ) {
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;
	
	if ( $line eq "" ) {
		if ( ! $sessionended ) {
			# Interactive ...
			my( $endflag ) = spellCheckSentence( \@currentsent );
					
			if ( $endflag ) {
				$sessionended = 1;
			}
		}
		
		foreach my $w ( @currentsent ) {
			print( COROUT join( "\t", @{ $w } ) . "\n" );
		}
		print( COROUT "\n" );
		
		@currentsent = ();
		next;
	}
	
	my( $form, $lemma, $msd ) = split( /\s+/, $line );
	
	push( @currentsent, [ $form, $lemma, $msd ] );
}

close( COR );
close( COROUT );

qx/mv -fv ${CORPUSFILE}.sav $CORPUSFILE/;

#Save TBL Extra
saveLexicon( \%ROEXTBL, $ADDTBLFILE );

############# End main.

sub spellCheckSentence( $ ) {
	my( $sent ) = $_[0];
	
	for ( my $i = 0; $i < scalar( @{ $sent } ); $i++ ) {
		my( $t ) = $sent->[$i];
		
		if ( $t->[1] =~ /^\(./ ) {
			# See if the word is in the extra TBL ...
			if ( exists( $ROEXTBL{$t->[0]} ) ) {
				$t->[1] =~ s/^\(.+?\)//;
				
				if ( exists( $ROEXTBL{$t->[0]}->{$t->[2]} ) ) {
					my( $lemmaok ) = 0;
					
					foreach my $l ( @{ $ROEXTBL{$t->[0]}->{$t->[2]} } ) {
						if ( $l eq $t->[1] ) {
							$lemmaok = 1;
							last;
						}
					}
					
					if ( ! $lemmaok ) {
						$t->[1] = join( "#,#", @{ $ROEXTBL{$t->[0]}->{$t->[2]} } );
					}
				}
				else {
					my( @plemmas ) = ();
					my( @pmsds ) = ();
					
					foreach my $m ( keys( %{ $ROEXTBL{$t->[0]} } ) ) {
						push( @pmsds, $m );
						
						foreach my $l ( @{ $ROEXTBL{$t->[0]}->{$m} } ) {
							push( @plemmas, $l );
						}
					}
					
					$t->[1] = join( "#,#", @plemmas );
					$t->[2] = join( "#,#", @pmsds );
				}
				
				next;
			} # end if word in extra tbl ...
			
			# Only spell-check the unknown words ...
			my( $tw ) = lc( $t->[0] );
			my( $twfc ) = substr( $tw, 0, 1 );
			my( @possiblecorrections ) = ();
						
			foreach my $w ( keys( %ROTBL ) ) {
				if ( $twfc eq substr( lc( $w ), 0, 1 ) ) {
					my( $wtsim ) = distance( $tw, lc( $w ) );
					
					if ( $wtsim <= 3 ) {
						# Found a similar word form ...
						foreach my $m ( keys( %{ $ROTBL{$w} } ) ) {
							foreach my $l ( @{ $ROTBL{$w}->{$m} } ) {
								if ( scalar( @possiblecorrections ) > 0 ) {
									if ( $possiblecorrections[0]->[0] > $wtsim ) {
										@possiblecorrections = ();
										push( @possiblecorrections, [ $wtsim, $w, $l, $m ] );
									}
									elsif ( $possiblecorrections[0]->[0] == $wtsim ) {
										push( @possiblecorrections, [ $wtsim, $w, $l, $m ] );
									}
								}
								else {
									push( @possiblecorrections, [ $wtsim, $w, $l, $m ] );
								}
							}
						}
					}
				} # if same first char
			} # end all TBL

			print( "\nCONTEXT:\n" );
			my( @context ) = ();
			
			for ( my $j = $i - 1; $j >= 0 && $j >= $i - 4; $j-- ) {
				unshift( @context,  $sent->[$j]->[0] . "/" . $sent->[$j]->[1] . "/" . $sent->[$j]->[2] );
			}

			if ( scalar( @context ) > 0 ) {
				print( join( " ", @context ) );
				@context = ();
			}
			
			print( color( "bright_red" ) );
			print( " " . $t->[0] . "/" . $t->[1] . "/" . $t->[2] . " " );
			print( color( "reset" ) );
			
			for ( my $j = $i + 1; $j < scalar( @{ $sent } ) && $j <= $i + 4; $j++ ) {
				push( @context,  $sent->[$j]->[0] . "/" . $sent->[$j]->[1] . "/" . $sent->[$j]->[2] );
			}
			
			if ( scalar( @context ) > 0 ) {
				print( join( " ", @context ) . "\n\n" );
				@context = ();
			}

			print( "SUGGESTIONS:\n" );
			my( @suggestions ) = ();
			
			$t->[1] =~ s/^\(.+?\)//;
			
			push( @suggestions, [ "EDIT" ] );
			push( @suggestions, [ $t->[0], $t->[1], $t->[2] ] );
			
			if ( scalar( @possiblecorrections ) > 0 ) {
				foreach my $pc ( @possiblecorrections ) {
					push( @suggestions, [ $pc->[1], $pc->[2], $pc->[3] ] );
				}
			}
			
			for ( my $i = 0; $i < scalar( @suggestions ); $i++ ) {
				print( "$i) " . join( "/", @{ $suggestions[$i] } ) . "\n" );
			}
			
			print( "Choose option: " );
			my $opt = <STDIN>;
			
			while ( $opt !~ /^quit$/i && ( $opt !~ /^[0-9]+$/ || $opt >= scalar( @suggestions ) ) ) {
				print( "Choose option: " );
				$opt = <STDIN>;
			}
			
			return 1 if ( $opt =~ /^quit$/i );
			
			if ( $opt == 0 ) {
				my $wf = $cygterm->readline( "Form:", $t->[0] );
				
				$wf =~ s/^\s+//;
				$wf =~ s/\s+$//;
				$t->[0] = $wf if ( $wf ne "" );

				my $lm = $cygterm->readline( "Lemma:", $t->[1] );
				
				$lm =~ s/^\s+//;
				$lm =~ s/\s+$//;
				$t->[1] = $lm if ( $lm ne "" );
				
				my $md = $cygterm->readline( "MSD:", $t->[2] );
				
				$md =~ s/^\s+//;
				$md =~ s/\s+$//;
				$t->[2] = $md if ( $md ne "" );
			}
			else {
				$t->[0] = $suggestions[$opt]->[0];
				$t->[1] = $suggestions[$opt]->[1];
				$t->[2] = $suggestions[$opt]->[2];
			}
			
			# Add new word to TBL extra
			if ( $opt == 0 || $opt == 1 ) {
				if ( ! exists( $ROEXTBL{$t->[0]} ) ) {
					$ROEXTBL{$t->[0]} = { $t->[2] => [ $t->[1] ] };
				}
				elsif ( ! exists( $ROEXTBL{$t->[0]}->{$t->[2]} ) ) {
					$ROEXTBL{$t->[0]}->{$t->[2]} = [ $t->[1] ];
				}
				else {
					my( $found ) = 0;
					
					foreach my $l ( @{ $ROEXTBL{$t->[0]}->{$t->[2]} } ) {
						if ( $l eq $t->[1] ) {
							$found = 1;
							last;
						}
					}
					
					push( @{ $ROEXTBL{$t->[0]}->{$t->[2]} }, $t->[1] ) if ( ! $found );
				}
			}
		} # end if unknown word
	} # end all sentence
	
	return 0;
}

sub saveLexicon( $$ ) {
	my( $lexicon, $ofile ) = @_;
	
	open( LEX, ">", $ofile ) or die( "spellcheck::saveLexicon: cannot open file '$ofile' !\n" );
	binmode( LEX, ":utf8" );
	
	foreach my $w ( sort keys( %{ $lexicon } ) ) {
		foreach my $m ( sort keys( %{ $lexicon->{$w} } ) ) {
			foreach my $l ( sort @{ $lexicon->{$w}->{$m} } ) {
				print( LEX $w . "\t" . $l . "\t" . $m . "\n" );
			}
		}
	}
	
	close( LEX );
}

sub readLexicon( $ ) {
	my( $lexFile ) = $_[0];
	my( %lexicon ) = ();

	open( LEX, "<", $lexFile ) or die( "spellcheck::readLexicon: cannot open file '$lexFile' !\n" );
	binmode( LEX, ":utf8" );
	
	while( my $line = <LEX> ) {
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		
		next if ( $line eq "" || $line =~ /^#/ );
		
		my( $wordform, $lemma, $msd ) = split( /\s+/, $line );
		
		$lemma = $wordform if ( $lemma eq "=" );
		
		$wordform =~ s/&abreve;/ă/g;
		$wordform =~ s/&Abreve;/Ă/g;
		$wordform =~ s/&acirc;/â/g;
		$wordform =~ s/&Acirc;/Â/g;
		$wordform =~ s/&icirc;/î/g;
		$wordform =~ s/&Icirc;/Î/g;
		$wordform =~ s/&scedil;/ș/g;
		$wordform =~ s/&Scedil;/Ș/g;
		$wordform =~ s/&tcedil;/ț/g;
		$wordform =~ s/&Tcedil;/Ț/g;

		$lemma =~ s/&abreve;/ă/g;
		$lemma =~ s/&Abreve;/Ă/g;
		$lemma =~ s/&acirc;/â/g;
		$lemma =~ s/&Acirc;/Â/g;
		$lemma =~ s/&icirc;/î/g;
		$lemma =~ s/&Icirc;/Î/g;
		$lemma =~ s/&scedil;/ș/g;
		$lemma =~ s/&Scedil;/Ș/g;
		$lemma =~ s/&tcedil;/ț/g;
		$lemma =~ s/&Tcedil;/Ț/g;
		
		if ( ! exists( $lexicon{$wordform} ) ) {
			$lexicon{$wordform} = { $msd => [ $lemma ] };
		}
		elsif ( ! exists( $lexicon{$wordform}->{$msd} ) ) {
			$lexicon{$wordform}->{$msd} = [ $lemma ];
		}
		else {
			my( $found ) = 0;
			
			foreach my $l ( @{ $lexicon{$wordform}->{$msd} } ) {
				if ( $l eq $lemma ) {
					$found = 1;
					last;
				}
			}
			
			push( @{ $lexicon{$wordform}->{$msd} }, $lemma ) if ( ! $found );
		}
	}
	
	close( LEX );
	return %lexicon;
}
