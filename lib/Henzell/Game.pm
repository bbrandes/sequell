package Henzell::Game;

use strict;
use warnings;

use File::Basename;
use File::Spec;

use lib File::Spec->catfile(dirname(__FILE__), '../../src');
use lib File::Spec->catfile(dirname(__FILE__), '..');

use Helper qw/demunge_xlogline serialize_time/;
use Henzell::Crawl;

my %adjective_skill_title =
  map(($_ => 1),
      ('Deadly Accurate', 'Spry', 'Covert', 'Unseen', 'Ignorant',
       'Cutthroat', 'Adept', 'Devout', 'Orthodox',
       'Immaculate', 'Meek', 'Gusty', 'Puny', 'Rampant', 'Pure',
       'Omniscient'));

# Uncool words intended to cause offence will be righteously filtered.
my $BANNED_WORDS_FILE = 'banned_words.txt';
my @banned_words;
my $banned_words_modtime;

sub load_banned_words {
  return unless -f $BANNED_WORDS_FILE;
  if (!defined($banned_words_modtime)
      || -M($BANNED_WORDS_FILE) < $banned_words_modtime)
  {
    $banned_words_modtime = -M($BANNED_WORDS_FILE);
    @banned_words = ();
    open my $inf, '<', $BANNED_WORDS_FILE or return;
    while (<$inf>) {
      chomp;
      s/^\s*#.*//;
      next unless /\S/;
      push @banned_words, split();
    }
    close $inf;
    print "Loaded ", scalar(@banned_words), " banned words\n";
  }
}

sub contains_banned_word {
  load_banned_words();
  for my $line (@_) {
    for my $word (@banned_words) {
      return 1 if $line =~ /\Q$word/i;
    }
  }
  return undef;
}

sub game_place_branch($) {
  my $g = shift;
  my $place = $$g{place};
  if ($place =~ /:/) {
    ($place) = $place =~ /(.*):/;
  }
  $place
}

sub game_skill_title
{
  my $game_ref = shift;
  my $title = $game_ref->{title};
  $title = skill_farming($title) if $game_ref->{turn} > 200000;
  my $article = ($title =~ /petite/i ? "La" : "the");
  $title = $article .  " " . $title unless $title =~ /^(the|le|la|l')\b/i;
  return $title;
}

sub skill_title_is_adjective($) {
  my $title = shift;
  $adjective_skill_title{$title} || $title =~ /(?:ly|ed|ble|ous|ish|id|ic|less|ing)$/
}

sub skill_farming
{
  my $title = shift;
  if ($title =~ /petite/i) {
    return "$title Fastidieuse";
  }
  elsif (skill_title_is_adjective($title)) {
    return "$title Farmer";
  }
  elsif ($title =~ /(Crazy|\w+'s) /) {
    $title =~ s/\Q($1)/$1 Farming/;
    return $title;
  }
  else {
    return "Farming $title";
  }
}

sub format_date {
  my $date = shift;
  return $date || '' unless value_is_date($date) &&
                     $date =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
  return $1 . "-" . sprintf("%02d", $2 + 1) . "-" . $3 . " $4:$5:$6";
}

sub value_is_date {
  my $value = shift;
  $value && $value =~ /^\d{4}\d{2}\d{2}\d{2}\d{2}\d{2}[SD]$/
}

sub formatted_game_field {
  my ($g, $field) = @_;
  if ($field =~ /\b(?:killer)?map\b/) {
    my $val = $$g{$field};
    $val =~ s/(?<!;) /_/g;
    $val
  } elsif (grep($_ eq $field, 'end', 'start', 'rend', 'rstart', 'time') ||
      $field =~ /^(?:day|year|month)\(/ ||
        value_is_date($$g{$field}))
  {
    return format_date($$g{$field}) . " [$$g{$field}]";
  }
  elsif ($field eq 'dur' && ($$g{field} || '') =~ /^\d+$/) {
    return serialize_time($$g{$field}) . " [$$g{$field}]";
  }
  else {
    return $$g{$field};
  }
}

sub parse_extras {
  my $game_ref = shift;
  my $extra = '';

  if ($$game_ref{extra}) {
    $extra = "[" . join(";",
                        map("$_=" . formatted_game_field($game_ref, $_),
                            split(/;;;;/, $$game_ref{extra}))) . "] ";
  }
  $extra
}

sub vault_name_transform($) {
  my $vault = shift;
  return $vault unless $vault;
  $vault =~ s/(?<!;) /_/g;
  $vault
}

sub game_place($) {
  my $g = shift;

  my $loc_string = "";
  my $place = $g->{place};

  my $sprint = Henzell::Crawl::game_is_sprint($g);

  $place = 'Sprint' if $sprint && $place eq 'D';

  my $qualifier = '';
  if ($$g{map}) {
    my $map = vault_name_transform($$g{map});
    $map = "$$g{mapdesc} : $map" if $$g{mapdesc};
    $map = $$g{mapdesc} if $$g{mapdesc} && $sprint;
    $qualifier = " ($map)"
  }

  my $prep = $place =~ /:/? 'on' : 'in';
  $place = "the $place" if grep($_ eq $place, qw/Temple Abyss/);
  $place = "a Labyrinth" if $place eq 'Lab';
  $place = "a Bazaar" if $place eq 'Bzr';
  $place = "Pandemonium" if $place eq 'Pan';
  $loc_string = " $prep $place$qualifier";

  $loc_string = "" # For escapes of the dungeon, so it doesn't print the loc
    if $g->{ktyp} eq 'winning' or $g->{ktyp} eq 'leaving';

  return $loc_string;
}

sub kmap_is_significant
{
  my $kmap = shift;
  $kmap && $kmap !~ /^uniq[ _]/;
}

sub game_string {
  my $game_ref = shift;
  my $extra = parse_extras($game_ref);

  my $loc_string = game_place($game_ref);

  my $death_date = " on " . format_date($$game_ref{end});
  my $deathmsg = $game_ref->{vmsg} || $game_ref->{tmsg};
  $deathmsg =~ s/[.!]+$//;
  my $killer_map = vault_name_transform($game_ref->{killermap});
  if (kmap_is_significant($killer_map) && !$game_ref->{map}) {
    $deathmsg .= " (kmap: $killer_map)";
  }

  my $title = game_skill_title($game_ref);
  sprintf '%s%s %s (L%d %s%s), %s%s%s, with %d point%s after %d turn%s and %s.',
      $extra,
      $game_ref->{name},
	  $title,
      $game_ref->{xl},
      $game_ref->{char},
      $game_ref->{god} ? " of $game_ref->{god}" : '',
      $deathmsg,
      $loc_string,
      $death_date,
      $game_ref->{sc},
      $game_ref->{sc} == 1 ? '' : 's',
      $game_ref->{turn},
      $game_ref->{turn} == 1 ? '' : 's',
      serialize_time($game_ref->{dur})
}

sub milestone_string
{
  my ($g, $show_time) = @_;
  my $extra = parse_extras($g);

  my $place = $$g{oplace} || $$g{place};
  my $placestring = " ($place)";

  my $ms = $$g{milestone};
  my $turn = $$g{turn};
  $ms =~ s/\.$/ on turn $turn./;

  my $time = format_date($$g{time});
  my $prefix = $show_time? "[" . $time . "] " : '';
  sprintf("$prefix%s%s %s (L%s %s%s) %s%s",
          $extra,
          $g->{name},
          game_skill_title($g),
          $g->{xl},
          $g->{char},
          $g->{god} ? " of $g->{god}" : '',
          $ms,
          $placestring)
}

1;
