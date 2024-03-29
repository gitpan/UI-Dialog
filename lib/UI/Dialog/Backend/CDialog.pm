package UI::Dialog::Backend::CDialog;
###############################################################################
#  Copyright (C) 2013  Kevin C. Krinke <kevin@krinke.ca>
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
###############################################################################
use 5.006;
use strict;
use Config;
use FileHandle;
use Carp;
use Cwd qw( abs_path );
use Time::HiRes qw( sleep );
use UI::Dialog::Backend;

BEGIN {
    use vars qw( $VERSION @ISA );
    @ISA = qw( UI::Dialog::Backend );
    $VERSION = '1.09';
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#: Constructor Method
#:

sub new {
    my $proto = shift();
    my $class = ref($proto) || $proto;
    my $cfg = ((ref($_[0]) eq "HASH") ? $_[0] : (@_) ? { @_ } : {});
    my $self = {};
    bless($self, $class);
    $self->{'_state'} = {};
    $self->{'_opts'} = {};

	#: Dynamic path discovery...
	my $path_sep = $Config::Config{path_sep};
	my $CFG_PATH = $cfg->{'PATH'};
	if ($CFG_PATH) {
		if (ref($CFG_PATH) eq "ARRAY") { $self->{'PATHS'} = $CFG_PATH; }
		elsif ($CFG_PATH =~ m!$path_sep!) { $self->{'PATHS'} = [ split(/$path_sep/,$CFG_PATH) ]; }
		elsif (-d $CFG_PATH) { $self->{'PATHS'} = [ $CFG_PATH ]; }
	} elsif ($ENV{'PATH'}) { $self->{'PATHS'} = [ split(/$path_sep/,$ENV{'PATH'}) ]; }
	else { $self->{'PATHS'} = ''; }

	$self->{'_opts'}->{'literal'} = $cfg->{'literal'} || 0;
    $self->{'_opts'}->{'callbacks'} = $cfg->{'callbacks'} || undef();
    $self->{'_opts'}->{'timeout'} = $cfg->{'timeout'} || 0;
    $self->{'_opts'}->{'wait'} = $cfg->{'wait'} || 0;
    $self->{'_opts'}->{'debug'} = $cfg->{'debug'} || undef();
    $self->{'_opts'}->{'title'} = $cfg->{'title'} || undef();
    $self->{'_opts'}->{'backtitle'} = $cfg->{'backtitle'} || undef();
    $self->{'_opts'}->{'width'} = $cfg->{'width'} || 65;
    $self->{'_opts'}->{'height'} = $cfg->{'height'} || 10;
    $self->{'_opts'}->{'percentage'} = $cfg->{'percentage'} || 1;
    $self->{'_opts'}->{'colours'} = ($cfg->{'colours'} || $cfg->{'colors'}) ? 1 : 0;
    $self->{'_opts'}->{'bin'} ||= $self->_find_bin('dialog');
    $self->{'_opts'}->{'bin'} ||= $self->_find_bin('dialog.exe') if $^O =~ /win32/i;
    $self->{'_opts'}->{'autoclear'} = $cfg->{'autoclear'} || 0;
    $self->{'_opts'}->{'clearbefore'} = $cfg->{'clearbefore'} || 0;
    $self->{'_opts'}->{'clearafter'} = $cfg->{'clearafter'} || 0;
    $self->{'_opts'}->{'beepbin'} = $cfg->{'beepbin'} || $self->_find_bin('beep') || '/usr/bin/beep';
    $self->{'_opts'}->{'beepbefore'} = $cfg->{'beepbefore'} || 0;
    $self->{'_opts'}->{'beepafter'} = $cfg->{'beepafter'} || 0;
    unless (-x $self->{'_opts'}->{'bin'}) {
		croak("the dialog binary could not be found at: ".$self->{'_opts'}->{'bin'});
    }
    $self->{'_opts'}->{'DIALOGRC'} = $cfg->{'DIALOGRC'} || undef();
    my $beginref = $cfg->{'begin'};
    $self->{'_opts'}->{'begin'} = (ref($beginref) eq "ARRAY") ? $beginref : undef();
    $self->{'_opts'}->{'cancel-label'} = $cfg->{'cancel-label'} || undef();
    $self->{'_opts'}->{'defaultno'} = $cfg->{'defaultno'} || 0;
    $self->{'_opts'}->{'default-item'} = $cfg->{'default-item'} || undef();
    $self->{'_opts'}->{'exit-label'} = $cfg->{'exit-label'} || undef();
    $self->{'_opts'}->{'extra-button'} = $cfg->{'extra-button'} || 0;
    $self->{'_opts'}->{'extra-label'} = $cfg->{'extra-label'} || undef();
    $self->{'_opts'}->{'help-button'} = $cfg->{'help-button'} || 0;
    $self->{'_opts'}->{'help-label'} = $cfg->{'help-label'} || undef();
    $self->{'_opts'}->{'max-input'} = $cfg->{'max-input'} || 0;
    $self->{'_opts'}->{'no-cancel'} = $cfg->{'no-cancel'} || $cfg->{'nocancel'} || 0;
    $self->{'_opts'}->{'no-collapse'} = $cfg->{'no-collapse'} || 0;
    $self->{'_opts'}->{'no-shadow'} = $cfg->{'no-shadow'} || 0;
    $self->{'_opts'}->{'ok-label'} = $cfg->{'ok-label'} || undef();
    $self->{'_opts'}->{'shadow'} = $cfg->{'shadow'} || 0;
    $self->{'_opts'}->{'tab-correct'} = $cfg->{'tab-correct'} || 0;
    $self->{'_opts'}->{'tab-len'} = $cfg->{'tab-len'} || 0;
    $self->{'_opts'}->{'listheight'} = $cfg->{'listheight'} || $cfg->{'menuheight'} || 5;
    $self->{'_opts'}->{'formheight'} = $cfg->{'formheight'} || $cfg->{'listheight'} || 5;
    $self->{'_opts'}->{'yes-label'} = $cfg->{'yes-label'} || undef();
    $self->{'_opts'}->{'no-label'} = $cfg->{'no-label'} || undef();

    $self->_determine_dialog_variant();
    return($self);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#: Private Methods
#:
sub _determine_dialog_variant {
    my $self = $_[0];
    my $str = `$self->{'_opts'}->{'bin'} --help 2>&1`;
    if ($str =~ /version\s0\.[34]/m) {
		# this version does not support colours, so far just FreeBSD 4.8 has this
		# ancient binary. Bugreport from Jeroen Bulten indicates that he's
		# got a version 0.3 (patched to 0.4) installed. ugh...
		$self->{'_variant'} = "dialog";
		# the separate-output option seems to be the culprit of FreeBSD failure.
		$self->{'_opts'}->{'force-no-separate-output'} = 1;
	} elsif ($str =~ /cdialog\s\(ComeOn\sDialog\!\)\sversion\s(\d+\.\d+.+)/) {
		# We consider cdialog to be a colour supporting dialog variant all others
		# are non-colourized and support only the base functionality :(
		my $ver = $1;
		if ($ver =~ /-200[3-9]/) {
			$self->{'_variant'} = "cdialog";
			# these versions support colours :)
			$self->{'_opts'}->{'colours'} = 1;
		} else {
			$self->{'_variant'} = "dialog";
		}
    } else { $self->{'_variant'} = "dialog"; }
    undef($str);
}

my $SIG_CODE = {};
sub _del_gauge {
    my $CODE = $SIG_CODE->{$$};
    unless (not ref($CODE)) {
		delete($CODE->{'_GAUGE'});
		$CODE->rv('1');
		$CODE->rs('null');
		$CODE->ra('null');
		$SIG_CODE->{$$} = "";
    }
}
sub _mk_cmnd {
    my $self = shift();
    my $final = shift();
    my $cmnd;
    my $args = $self->_merge_attrs(@_);

    $ENV{'DIALOGRC'} ||= ($args->{'DIALOGRC'} && -r $args->{'DIALOGRC'}) ? $args->{'DIALOGRC'} : "";
    $ENV{'DIALOG_CANCEL'} = '1';
    $ENV{'DIALOG_ERROR'}  = '254';
    $ENV{'DIALOG_ESC'}    = '255';
    $ENV{'DIALOG_EXTRA'}  = '3';
    $ENV{'DIALOG_HELP'}   = '2';
    $ENV{'DIALOG_OK'}     = '0';

    $cmnd = $self->{'_opts'}->{'bin'};

    $cmnd .= ' --title "' . ($args->{'title'} || $self->{'_opts'}->{'title'}) . '"'
     unless not $args->{'title'} and not $self->{'_opts'}->{'title'};
    $cmnd .= ' --backtitle "' . ($args->{'backtitle'} || $self->{'_opts'}->{'backtitle'}) . '"'
     unless not $args->{'backtitle'} and not $self->{'_opts'}->{'backtitle'};
	$cmnd .= ' --separate-output' unless $self->{'_opts'}->{'force-no-separate-output'}
	 or (not $args->{'separate-output'} and not $self->{'_opts'}->{'separate-output'});
    if ($self->is_cdialog()) {
		$cmnd .= ' --colors';
		$cmnd .= ' --cr-wrap';
		# --begin <x> <y>
		my $begin = $args->{'begin'};
		if (ref($begin) eq "ARRAY") {
			$cmnd .= ' --begin '.$begin->[0].' '.$begin->[1];
		}
		$cmnd .= ' --cancel-label "'.$args->{'cancel-label'}.'"' unless not $args->{'cancel-label'};
		$cmnd .= ' --defaultno' unless not $args->{'defaultno'};
		$cmnd .= ' --default-item "'.$args->{'default-item'}.'"' unless not $args->{'default-item'};
		$cmnd .= ' --exit-label "'.$args->{'exit-label'}.'"' unless not $args->{'exit-label'};
		$cmnd .= ' --extra-button' unless not $args->{'extra-button'} and not $args->{'extra-label'};
		$cmnd .= ' --extra-label "'.$args->{'extra-label'}.'"' unless not $args->{'extra-label'};
		$cmnd .= ' --help-button' unless not $args->{'help-button'} and not $args->{'help-label'};
		$cmnd .= ' --help-label "'.$args->{'help-label'}.'"' unless not $args->{'help-label'};
		$cmnd .= ' --max-input "'.$args->{'max-input'}.'"' unless not $args->{'max-input'};
		$cmnd .= ' --no-cancel' unless not $args->{'nocancel'} and not $args->{'no-cancel'};
		$cmnd .= ' --no-collapse' unless not $args->{'no-collapse'} and not $args->{'literal'};
		$cmnd .= ' --no-shadow' unless not $args->{'no-shadow'};
		$cmnd .= ' --ok-label "'.$args->{'ok-label'}.'"' unless not $args->{'ok-label'};
		$cmnd .= ' --shadow' unless not $args->{'shadow'};
		$cmnd .= ' --tab-correct' unless not $args->{'tab-correct'};
		$cmnd .= ' --tab-len "'.$args->{'tab-len'}.'"' unless not $args->{'tab-len'};
		$cmnd .= ' --yes-label "'.$args->{'yes-label'}.'"' unless not $args->{'yes-label'};
		$cmnd .= ' --no-label "'.$args->{'no-label'}.'"' unless not $args->{'no-label'};

		# --item-help                        #<-- NEEDS WORK
		# --no-kill                          #<-- tailboxbg only

    }
    $cmnd .= " " . $final;
    return($cmnd);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#: Override Inherited Methods
#:
sub command_state {
    my $self = $_[0];
    my $cmnd = $_[1];
    $self->_debug("".$cmnd);
    my $null_dev = $^O =~ /win32/i ? 'NUL:' : '/dev/null';
    system($cmnd . " 2> $null_dev");
    return($? >> 8);
}
sub command_string {
    my $self = $_[0];
    my $cmnd = $_[1];
    $self->_debug($cmnd);
    $self->gen_tempfile_name(); # don't accept the first result
    my $tmpfile = $self->gen_tempfile_name();
    my $text;
    system($cmnd." 2> ".$tmpfile);
    my $rv = $? >> 8;
    if (-f $tmpfile # don't assume the file exists
		&& open(WHIPF,"<".$tmpfile)) {
		local $/;
		$text = <WHIPF>;
		close(WHIPF);
		unlink($tmpfile);
    } else { $text = ""; }
    return($text) unless defined wantarray;
    return (wantarray) ? ($rv,$text) : $text;
}
sub command_array {
    my $self = $_[0];
    my $cmnd = $_[1];
    $self->_debug($cmnd);
    $self->gen_tempfile_name(); # don't accept the first result
    my $tmpfile = $self->gen_tempfile_name();
    my $text;
    system($cmnd." 2> ".$tmpfile);
    my $rv = $? >> 8;
    if (-f $tmpfile # don't assume the file exists
		&& open(WHIPF,"<".$tmpfile)) {
		local $/;
		$text = <WHIPF>;
		close(WHIPF);
		unlink($tmpfile);
    } else { $text = ""; }
	if ($self->{'_opts'}->{'force-no-separate-output'}) {
		# a side effect of this forcible backwards compatibility is that any
		# "tags" with spaces will get broken down. *shrugs* Not much I can
		# do about this and because it's a minority of users with these
		# ancient versions of dialog I'm not delving any deeper into it.
		return([split(/\s/,$text)]) unless defined wantarray;
		return (wantarray) ? ($rv,[split(/\s/,$text)]) : [split(/\s/,$text)];
	} else {
		return([split("\n",$text)]) unless defined wantarray;
		return (wantarray) ? ($rv,[split("\n",$text)]) : [split("\n",$text)];
	}
}
sub _organize_text {
    my $self = $_[0];
    my $text = $_[1] || return();
    my $width = $_[2] || 65;
    my @array;

    if (ref($text) eq "ARRAY") { push(@array,@{$text}); }
    elsif ($text =~ /\\n/) { @array = split(/\\n/,$text); }
    else { @array = split(/\n/,$text); }
    $text = undef();

    @array = $self->word_wrap($width,"","",@array);
    my $max = @array;
    for (my $i = 0; $i < $max; $i++) { $array[$i] = $self->_esc_text($array[$i]); }

    if ($self->{'scale'}) {
		foreach my $line (@array) {
			my $s_line = $self->__TRANSLATE_CLEAN($line);
			$s_line =~ s!\[A\=\w+\]!!gi;
			$self->{'width'} = length($s_line) + 5
			 if ($self->{'width'} - 5) < length($s_line)
			  && (length($s_line) <= $self->{'max-scale'});
		}
    }

    my $new_line = $^O =~ /win32/i ? '\n' : "\n";
    foreach my $line (@array) {
		my $pad;
		my $s_line = $self->_strip_text($line);
		if ($line =~ /\[A\=(\w+)\]/i) {
			my $align = $1;
			$line =~ s!\[A\=\w+\]!!gi;
			if (uc($align) eq "CENTER" || uc($align) eq "C") {
				$pad = ((($self->{'_opts'}->{'width'} - 5) - length($s_line)) / 2);
				#		$pad = (($self->{'_opts'}->{'width'} - length($s_line)) / 2);
			} elsif (uc($align) eq "LEFT" || uc($align) eq "L") {
				$pad = 0;
			} elsif (uc($align) eq "RIGHT" || uc($align) eq "R") {
				$pad = (($self->{'_opts'}->{'width'} - 5) - length($s_line));
				#		$pad = (($self->{'_opts'}->{'width'}) - length($s_line));
			}
		}
		if ($pad) { $text .= (" " x $pad).$line.$new_line; }
		else { $text .= $line . $new_line; }
    }
    return($self->_filter_text($text));
}
sub _strip_text {
    my $self = shift();
    my $text = shift();
    $text =~ s!\\Z0!!gmi;
    $text =~ s!\\Z1!!gmi;
    $text =~ s!\\Z2!!gmi;
    $text =~ s!\\Z3!!gmi;
    $text =~ s!\\Z4!!gmi;
    $text =~ s!\\Z5!!gmi;
    $text =~ s!\\Z6!!gmi;
    $text =~ s!\\Z7!!gmi;
    $text =~ s!\\Zb!!gmi;
    $text =~ s!\\ZB!!gmi;
    $text =~ s!\\Zu!!gmi;
    $text =~ s!\\ZU!!gmi;
    $text =~ s!\\Zr!!gmi;
    $text =~ s!\\ZR!!gmi;
    $text =~ s!\\Zn!!gmi;
    $text =~ s!\[C=black\]!!gmi;
    $text =~ s!\[C=red\]!!gmi;
    $text =~ s!\[C=green\]!!gmi;
    $text =~ s!\[C=yellow\]!!gmi;
    $text =~ s!\[C=blue\]!!gmi;
    $text =~ s!\[C=magenta\]!!gmi;
    $text =~ s!\[C=cyan\]!!gmi;
    $text =~ s!\[C=white\]!!gmi;
    $text =~ s!\[B\]!!gmi;
    $text =~ s!\[/B\]!!gmi;
    $text =~ s!\[U\]!!gmi;
    $text =~ s!\[/U\]!!gmi;
    $text =~ s!\[R\]!!gmi;
    $text =~ s!\[/R\]!!gmi;
    $text =~ s!\[N\]!!gmi;
    $text =~ s!\[A=\w+\]!!gmi;
    return($text);
}
sub _filter_text {
    my $self = shift();
    my $text = shift() || return();
    if ($self->is_cdialog() && $self->{'_opts'}->{'colours'}) {
		$text =~ s!\[C=black\]!\\Z0!gmi;
		$text =~ s!\[C=red\]!\\Z1!gmi;
		$text =~ s!\[C=green\]!\\Z2!gmi;
		$text =~ s!\[C=yellow\]!\\Z3!gmi;
		$text =~ s!\[C=blue\]!\\Z4!gmi;
		$text =~ s!\[C=magenta\]!\\Z5!gmi;
		$text =~ s!\[C=cyan\]!\\Z6!gmi;
		$text =~ s!\[C=white\]!\\Z7!gmi;
		$text =~ s!\[B\]!\\Zb!gmi;
		$text =~ s!\[/B\]!\\ZB!gmi;
		$text =~ s!\[U\]!\\Zu!gmi;
		$text =~ s!\[/U\]!\\ZU!gmi;
		$text =~ s!\[R\]!\\Zr!gmi;
		$text =~ s!\[/R\]!\\ZR!gmi;
		$text =~ s!\[N\]!\\Zn!gmi;
		$text =~ s!\[A=\w+\]!!gmi;
		return($text);
    } else {
		return($self->_strip_text($text));
    }
}


#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#: Public Methods
#:

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: test for the good stuff
sub is_cdialog {
    my $self = $_[0];
    return(1) if $self->{'_variant'} && $self->{'_variant'} eq "cdialog";
    return(0);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: Ask a binary question (Yes/No)
sub yesno {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(' --yesno',@_);
	$command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my $rv = $self->command_state($command);
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->ra("NO");
		$self->rs("NO");
		$self->rv($rv);
		$this_rv = 0;
    } else {
		$self->ra("YES");
		$self->rs("YES");
		$self->rv('null');
		$this_rv = 1;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: Text entry
sub inputbox {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $cmnd_prefix = ' --inputbox';
    if ($args->{'password'}) { $cmnd_prefix = ' --passwordbox'; }
    my $command = $self->_mk_cmnd($cmnd_prefix,@_);
	$command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'init'}||$args->{'entry'}||'') . '"'
     unless not $args->{'init'} and not $args->{'entry'};

    my ($rv,$text) = $self->command_string($command);
    $self->ra('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->rs('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->rs($text);
		$self->ra($text);
		$this_rv = $text;
    }
    $self->_post($args);
    return($this_rv);
}
#: password boxes aren't supported by gdialog
sub password {
    my $self = shift();
    return($self->inputbox('caller',((caller(1))[3]||'main'),@_,'password',1));
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: Text box
sub msgbox {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    $args->{'msgbox'} ||= 'msgbox';

    my $command = $self->_mk_cmnd(' --'.$args->{'msgbox'},@_);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my $rv = $self->command_state($command);
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$this_rv = 0;
    } else {
		if (($args->{'msgbox'} eq "infobox") && ($args->{'timeout'} || $args->{'wait'})) {
			my $s = int(($args->{'wait'}) ? $args->{'wait'} :
						($args->{'timeout'}) ? ($args->{'timeout'} / 1000.0) : 1.0);
			sleep($s);
		}
		$self->rv('null');
		$this_rv = 1;
    }
    $self->_post($args);
    return($this_rv);
}
sub infobox {
    my $self = shift();
    return($self->msgbox('caller',((caller(1))[3]||'main'),@_,'msgbox','infobox'));
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: File box
sub textbox {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --textbox",@_);
    $command .= ' "' . ($args->{'path'}||'.') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my ($rv,$text) = $self->command_string($command);
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$this_rv = 0;
    } else {
		$self->rv('null');
		$this_rv = 1;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: a simple menu
sub menu {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --menu",@_);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'menuheight'}||$args->{'listheight'}||'5') . '"';

    if ($args->{'list'}) {
		$args->{'list'} = [ ' ', ' ' ] unless ref($args->{'list'}) eq "ARRAY";
		foreach my $item (@{$args->{'list'}}) {
			$command .= ' "' . ($item||' ') . '"';
		}
    } else {
		$args->{'items'} = [ ' ', ' ' ] unless ref($args->{'items'}) eq "ARRAY";
		foreach my $item (@{$args->{'items'}}) {
			$command .= ' "' . ($item||' ') . '"';
		}
    }

    my ($rv,$selected) = $self->command_string($command);
    $self->ra('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->rs('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->rs($selected);
		$this_rv = $selected;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: a check list
sub checklist {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    $self->{'checklist'} ||= 'checklist';

    my $command = $self->_mk_cmnd(" --".$self->{'checklist'},@_,'separate-output',1);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'menuheight'}||$args->{'listheight'}||'5') . '"';

    if ($args->{'list'}) {
		$args->{'list'} = [ ' ', [' ', 1] ] unless ref($args->{'list'}) eq "ARRAY";
		my ($item,$info);
		while (@{$args->{'list'}}) {
			$item = shift(@{$args->{'list'}});
			$info = shift(@{$args->{'list'}});
			$command .= ' "'.($item||' ').'" "'.($info->[0]||' ').'" "'.(($info->[1]) ? 'on' : 'off').'"';
		}
    } else {
		$args->{'items'} = [ ' ', ' ', 'off' ] unless ref($args->{'items'}) eq "ARRAY";
		foreach my $item (@{$args->{'items'}}) {
			$command .= ' "' . ($item|' ') . '"';
		}
    }
    my ($rv,$selected) = $self->command_array($command);
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->ra('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->ra(@$selected);
		$self->rs(join("\n",@$selected));
		$this_rv = $selected;
    }
    $self->_post($args);
    return($this_rv) unless ref($this_rv) eq "ARRAY";
    return(@{$this_rv});
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: a radio button list
sub radiolist {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    $self->{'radiolist'} ||= 'radiolist';

    my $command = $self->_mk_cmnd(" --".$self->{'radiolist'},@_);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'menuheight'}||$args->{'listheight'}||'5') . '"';

    if ($args->{'list'}) {
		$args->{'list'} = [ ' ', [' ', 1] ] unless ref($args->{'list'}) eq "ARRAY";
		my ($item,$info);
		while (@{$args->{'list'}}) {
			$item = shift(@{$args->{'list'}});
			$info = shift(@{$args->{'list'}});
			$command .= ' "'.($item||' ').'" "'.($info->[0]||' ').'" "'.(($info->[1]) ? 'on' : 'off').'"';
		}
    } else {
		$args->{'items'} = [ ' ', ' ', 'off' ] unless ref($args->{'items'}) eq "ARRAY";
		foreach my $item (@{$args->{'items'}}) {
			$command .= ' "' . ($item||' ') . '"';
		}
    }

    my ($rv,$selected) = $self->command_string($command);
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->ra('null');
		$self->rs('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->ra($selected);
		$self->rs($selected);
		$this_rv = $selected;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: file select
sub fselect {
    my $self = shift();

    unless ($self->is_cdialog()) {
		return($self->SUPER::fselect(@_));
    }

    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --fselect",@_);
    $command .= ' "' . ($args->{'path'}||abs_path()) . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my ($rv,$file) = $self->command_string($command);
    $self->ra('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->rs('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->rs($file);
		$self->ra($file);
		$this_rv = $file;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: calendar

sub calendar {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --calendar",@_);
    $command .= ' "' . ($args->{'text'}||'') . '"';
    $command .= ' "' . ($args->{'height'}||'6') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'day'}||'') . '"';
    $command .= ' "' . ($args->{'month'}||'') . '"';
    $command .= ' "' . ($args->{'year'}||'') . '"';

    my ($rv,$date) = $self->command_string($command);
    $self->ra('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->rs('null');
		$this_rv = 0;
    } else {
		chomp($date);
		$self->rv('null');
		$self->rs($date);
		$self->ra(split(/\//,$date));
		$this_rv = $date;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: timebox

sub timebox {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    my $command = $self->_mk_cmnd(" --timebox",@_);
    $command .= ' "' . ($args->{'text'}||'') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'hour'}||$hour) . '"';
    $command .= ' "' . ($args->{'minute'}||$min) . '"';
    $command .= ' "' . ($args->{'second'}||$sec) . '"';

    my ($rv,$time) = $self->command_string($command);
    $self->ra('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->rs('null');
		$this_rv = 0;
    } else {
		chomp($time);
		$self->rv('null');
		$self->rs($time);
		$self->ra(split(/\:/,$time));
		$this_rv = $time;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: tailbox

sub tailbox {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --tailbox",@_);
    $command .= ' "' . ($args->{'path'}||'') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my ($rv) = $self->command_state($command);
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$this_rv = 0;
    } else {
		$self->rv('null');
		$this_rv = 1;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: tailboxbg

sub tailboxbg {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    my $command = $self->_mk_cmnd(" --tailboxbg",@_);
    $command .= ' "' . ($args->{'path'}||'') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';

    my ($rv) = $self->command_state($command);
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$this_rv = 0;
    } else {
		$self->rv('null');
		$this_rv = 1;
    }
    $self->_post($args);
    return($this_rv);
}

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: an editable form (wow is this useful! holy cripes!)
sub form {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    $self->{'form'} ||= 'form';

    my $command = $self->_mk_cmnd(" --".$self->{'form'},@_);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'30') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'formheight'}||$args->{'menuheight'}||$args->{'listheight'}||'5') . '"';

	# <label1> <l_y1> <l_x1> <item1> <i_y1> <i_x1> <flen1> <ilen1>
	# [ [ 'label1', 1, 1 ], [ 'item1', 1, 5, 10, 10 ], ... ]

	$args->{'list'} = [ [ 'bad', 1, 1 ], [ 'list', 1, 5, 4, "0" ] ] unless ref($args->{'list'}) eq "ARRAY";
	my ($item,$info);
	while (@{$args->{'list'}}) {
		$item = shift(@{$args->{'list'}}) || [ 'bad', 1, 1 ];
		$info = shift(@{$args->{'list'}}) || [ 'list', 1, 5, 4, "0" ];
		$command .= ' "'.($item->[0]||' ').'" "'.$item->[1].'" "'.$item->[2].'" "'.($info->[0]||' ').'" "'.$info->[1].'" "'.$info->[2].'" "'.$info->[3].'" "'.$info->[4].'"';
	}

    my ($rv,$selected) = $self->command_array($command);
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) {
		$self->rv($rv);
		$self->ra('null');
		$this_rv = 0;
    } else {
		$self->rv('null');
		$self->ra(@$selected);
		$self->rs(join("\n",@$selected));
		$this_rv = $selected;
    }
    $self->_post($args);
    return($this_rv) unless ref($this_rv) eq "ARRAY";
    return(@{$this_rv});
}

# #:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# #: inputmenu

# sub inputmenu {
#     my $self = shift();
#     my $args = $self->_merge_attrs(@_);

#     $self->_beep($args->{'beepbefore'});

#     my ($rv,$list) = (0,($args->{'list'}||$args->{'items'}));
#   INPUTMENULOOP: while (1) {

# 	my $command = $self->_mk_cmnd(" --inputmenu",@_);
# 	$command .= ' "' . ($args->{'text'}||'') . '"';
# 	$command .= ' "' . ($args->{'height'}||'20') . '"';
# 	$command .= ' "' . ($args->{'width'}||'65') . '"';
# 	$command .= ' "' . ($args->{'list-height'}||'10') . '"';

# 	$list = [ ' ', ' ' ] unless ref($list) eq "ARRAY";
# 	foreach my $item (@{$list}) {
# 	    $command .= ' "' . ($item||' ') . '"';
# 	}

# 	($rv,$list) = $self->command_array($command);
# 	$self->rs('null');
# 	if ($rv && $rv >= 1) {
# 	    $self->rv($rv);
# 	    $self->ra('null');
# 	    # return(0);
# 	} else {
# 	    $self->rv('null');
# 	    $self->ra($list);
# 	    # return($list);
# 	}

# 	use Data::Dumper;
# 	if ($self->state() eq "EXTRA" && $list->[0] =~ /^.*RENAMED\s([+)\s(.+)$/) {
# 	    my ($RTag,$RName) = ($1,$2);
# 	    my $alt_list = [];
# 	    while (@$list) {
# 		my $item = shift(@$list);
# 		my $name = shift(@$list);
# 		if ($item eq $RTag) {
# 		    push(@$alt_list,$item,$RName);
# 		} else {
# 		    push(@$alt_list,$item,$name);
# 		}
# 		print "$item $name\n"; sleep(1);
# 	    }
# 	    print Dumper($RTag,$RName,$alt_list); sleep(2);
# 	    $list = $alt_list;
# 	    next INPUTMENULOOP;
# 	}
# 	last INPUTMENULOOP;
#     }

#     $self->_beep($args->{'beepafter'});
#     $self->rs('null');
#     if ($rv && $rv >= 1) {
# 	$self->rv($rv);
# 	$self->ra('null');
# 	return(0);
#     } else {
# 	$self->rv('null');
# 	$self->ra($list);
# 	return($list);
#     }
# }

#:+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#: progress meter
sub gauge_start {
    my $self = shift();
    my $caller = (caller(1))[3] || 'main';
    $caller = ($caller =~ /^UI\:\:Dialog\:\:Backend\:\:/) ? ((caller(2))[3]||'main') : $caller;
    if ($_[0] && $_[0] eq 'caller') { shift(); $caller = shift(); }
    my $args = $self->_pre($caller,@_);

    $self->{'_GAUGE'} ||= {};
    $self->{'_GAUGE'}->{'ARGS'} = $args;

    if (defined $self->{'_GAUGE'}->{'FH'}) {
		$self->rv(129);
		$self->_post($args);
		return(0);
    }

    my $command = $self->_mk_cmnd(" --gauge",@_);
    $command .= ' "' . (($args->{'literal'} ? $args->{'text'} : $self->_organize_text($args->{'text'}))||' ') . '"';
    $command .= ' "' . ($args->{'height'}||'20') . '"';
    $command .= ' "' . ($args->{'width'}||'65') . '"';
    $command .= ' "' . ($args->{'percentage'}||'0') . '"';

    $self->{'_GAUGE'}->{'FH'} = new FileHandle;
    $self->{'_GAUGE'}->{'FH'}->open("| $command");
    my $rv = $? >> 8;
    $self->{'_GAUGE'}->{'FH'}->autoflush(1);
    $self->rv($rv||'null');
    $self->ra('null');
    $self->rs('null');
    my $this_rv;
    if ($rv && $rv >= 1) { $this_rv = 0; }
    else { $this_rv = 1; }
    return($this_rv);
}
sub gauge_inc {
    my $self = $_[0];
    my $incr = $_[1] || 1;

    return(0) unless defined $self->{'_GAUGE'}->{'FH'};

    my $fh = $self->{'_GAUGE'}->{'FH'};
    $self->{'_GAUGE'}->{'PERCENT'} += $incr;
    $SIG_CODE->{$$} = $self; local $SIG{'PIPE'} = \&_del_gauge;
    print $fh $self->{'_GAUGE'}->{'PERCENT'}."\n";
    return(((defined $self->{'_GAUGE'}->{'FH'}) ? 1 : 0));
}
sub gauge_dec {
    my $self = $_[0];
    my $decr = $_[1] || 1;

    return(0) unless defined $self->{'_GAUGE'}->{'FH'};

    my $fh = $self->{'_GAUGE'}->{'FH'};
    $self->{'_GAUGE'}->{'PERCENT'} -= $decr;
    $SIG_CODE->{$$} = $self; local $SIG{'PIPE'} = \&_del_gauge;
    print $fh $self->{'_GAUGE'}->{'PERCENT'}."\n";
    return(((defined $self->{'_GAUGE'}->{'FH'}) ? 1 : 0));
}
sub gauge_set {
    my $self = $_[0];
    my $perc = $_[1] || $self->{'_GAUGE'}->{'PERCENT'} || 1;

    return(0) unless $self->{'_GAUGE'}->{'FH'};

    my $fh = $self->{'_GAUGE'}->{'FH'};
    $self->{'_GAUGE'}->{'PERCENT'} = $perc;
    $SIG_CODE->{$$} = $self; local $SIG{'PIPE'} = \&_del_gauge;
    print $fh $self->{'_GAUGE'}->{'PERCENT'}."\n";
    return(((defined $self->{'_GAUGE'}->{'FH'}) ? 1 : 0));
}
# funky flicker... grr
sub gauge_text {
    my $self = $_[0];
    my $mesg = $_[1] || return(0);

    return(0) unless $self->{'_GAUGE'}->{'FH'};

    my $fh = $self->{'_GAUGE'}->{'FH'};
    $SIG_CODE->{$$} = $self; local $SIG{'PIPE'} = \&_del_gauge;
    print $fh "\nXXX\n\n".$mesg."\n\nXXX\n\n".$self->{'_GAUGE'}->{'PERCENT'}."\n";
    return(((defined $self->{'_GAUGE'}->{'FH'}) ? 1 : 0));
}
sub gauge_stop {
    my $self = $_[0];

    return(0) unless $self->{'_GAUGE'}->{'FH'};

    my $args = $self->{'_GAUGE'}->{'ARGS'};
    my $fh = $self->{'_GAUGE'}->{'FH'};
    $SIG_CODE->{$$} = $self; local $SIG{'PIPE'} = \&_del_gauge;
    $self->{'_GAUGE'}->{'FH'}->close();
    delete($self->{'_GAUGE'}->{'FH'});
    delete($self->{'_GAUGE'}->{'ARGS'});
    delete($self->{'_GAUGE'}->{'PERCENT'});
    delete($self->{'_GAUGE'});
    $self->rv('null');
    $self->rs('null');
    $self->ra('null');
    $self->_post($args);
    return(1);
}


1;

