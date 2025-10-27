use utf8;

#System Name
Set( $rtname, 'Example Corp.' );

#Database connection settings
Set( $DatabaseRTHost, "%" ) ;
Set( $DatabaseHost, 'db.example.com' );
Set( $DatabaseName, 'rt5' );
Set( $DatabasePassword, 'rt_pass' );
Set( $DatabasePort, '' );
Set( $DatabaseType, 'mysql' );
Set( $DatabaseUser, 'rt_user' );

#Logging settings
#debug info notice warning error critical alert emergency
Set( $LogToSyslog, "info");
Set( $LogToSTDERR, "info");

#Email settings
Set( $MailCommand, "sendmail");
Set( $SendmailPath, "/usr/bin/msmtp") ;
Set( $SendmailArguments, "-t" ) ;
Set( $CorrespondAddress, 'rt@example.com' );
Set( $CommentAddress, 'rt-comment@example.com' );

#Web settings
Set( $WebSecureCookies, 0);
Set( $WebDomain, 'rt.example.com' );
Set( $WebPort, '8080' );

#Application behavior settings
Set( $NotifyActor, 1);
Set( %ExternalStorage,
        Type => 'Disk',
        Path => '/attachments',
);
1;

