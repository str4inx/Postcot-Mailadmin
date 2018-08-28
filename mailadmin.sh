#!/bin/bash

# Name: mailadmin
# Author Robin Dost
# Last_edit 23.08.2018
# 
# Error Codes:
# 
#	604 - File not found
#	Mailadmin couldn't find some important files.
# 	Check the given source for more information
#	205 - Illegal string length error
#	You may entered an invalid string for a new user
#	Check the given source for more information
# 	Also check the RFC3936 for valid mail adresses
#	http://www.rfc-editor.org/rfc/rfc3696.txt
#	505 - Unsafe deletion error
#	Mailadmin only allows the deletion of mailbox Folders


printerr() {

	case $1 in 
		604) 
			echo "File not found error. $1."
			;;
		205)
			echo "Illegal string length error. $1"
			;;
		505)
			echo "Unsafe deletion error. $1 "
			;;
		*) echo "An error occured. Error 900"
			;;
	esac

	if [ "$2" != "" ];
		then
			echo "Source: '$2'"
		else
			echo "Source unknown"
	fi
	echo "Exit."
	exit

}


readonly PREFIX="[Mailadmin] - "

# Paths
readonly DOVECOT_PATH="/etc/dovecot/"
readonly POSTFIX_PATH="/etc/postfix/"
MAILDIR_PATH="/opt/dovecot/"

# Files
readonly ALIAS_FILE="/etc/postfix/vmail_aliases"
readonly PASSWD_FILE="/etc/dovecot/passwd"

# etc
readonly IDENT="<<"

USER_SELECTED=""
DOMAIN=""
ARRUSERS=""
USER_BLANK=""
OPTION=""
EXIT_CODE=0

# Check all files and directorys wether they exist
check_files(){

	files=("$PASSWD_FILE", "$ALIAS_FILE")

	# Loop through files array
	for f in "${files[@]}"
		do
			# If file does not exist
			if [ ! -f $f ];
				then	
					printerr 604 "$f"
			fi
		done
}

# Select users of a specific domain from /etc/dovecot/dovegui/users
get_users(){
	#declare -g ARRUSERS=($(grep "@$DOMAIN" $MAILADMIN_PATH"users"))
	declare -g ARRUSERS=($(cat /etc/dovecot/passwd | cut -d: -f1 | grep "$DOMAIN" | tr '\n' ' '))
}

# Check if user exists in users file
check_user(){
	return $(grep -Fxq "$USER_SELECTED" $MAILADMIN_PATH"users")
}

# Adds a mail user to the system
add_user(){
	 # User input
	USR=$(whiptail --inputbox "New Username:" 10 30 3>&1 1>&2 2>&3)
	# If not canceled
	if [ "$USR" != "" ]; 
		then
			# TODO: IF USER LENGTH BIGGER THEN ?30
			if [ ${#USR} -ge 64 ];
				then
					printerr 205 "$USR@$DOMAIN"
				else
					# If user doesn't exist
					if ! $(check_user)
						then
							# Notification
							whiptail --msgbox "Username successfully set!" 10 30
							# Create a new password
							pw="$(new_password)"
							# If password entry not canceled
							if [ "$pw" != "" ]; 
								then
									# Write user entry into passwd file
									echo "$USR@$DOMAIN:$pw::::::" >> "$PASSWD_FILE"  
									# Create inbox for user
									doveadm mailbox create -s -u "$USR@$DOMAIN" "INBOX" 
								else
									# Set exit code
									declare -g EXIT_CODE=1 
							fi
						else
							# Notification
							whiptail --msgbox "Username already exist!" 10 30
							# Go to add_user
							add_user
					fi
			fi
		else
			# Confirm action
			answer=$(whiptail --yesno "Are you sure?" 0 0 3>&1 1>&2 2>&3; echo $?)
			
			# If clicked "Yes"
			if [ "	$answer" -eq 0 ]; 
				then 
					# Set exit code
					declare -g EXIT_CODE=1
				else
					# Go to add_user
					add_user
			fi
	fi
}
# Removes a user on the mailsystem
remove_user(){
	# Confirm action
	answer=$(whiptail --yesno "Delete user $USER ?" 0 0 3>&1 1>&2 2>&3; echo $?)
	# If clicked "Yes"
	if [ $answer == 0 ]; 
		then			
			# Remove user entry from passwd file
			sed -i "/$USER_SELECTED/d" "$PASSWD_FILE"		
			# Remove users mail directory
			remove_safe "$MAILDIR_PATH"
			# Removes all aliases of a user
			rm -rf `doveadm user -f home $USER_SELECTED`		
			# Reload dovecot
			service dovecot reload
		else
			# Set exit code
			declare -g EXIT_CODE=2
	fi
}

# User editor interface
user_option() {
	# Selection menu
	choice=$(
	whiptail --title "${PREFIX}User Administration" --notags --cancel-button "Quit" --menu  "Select option:" 10 0 0 "$IDENT" "<< Back" 1 "Add user" \
																	2 "Edit user" 3>&1 1>&2 2>&3
			)
	# If not canceled
	if [ "$choice" != "" ]; 
		then
			if [ "$choice" == "$IDENT" ];
				then
					# Set exit code
					declare -g EXIT_CODE=3
				else
					# Set global var to selected option
					declare -g OPTION=$choice
					# Go to user_edit_option
					user_edit_option
			fi
		else
			#Set exit code
			declare -g EXIT_CODE=900
	fi
}

# User editor interface
user_edit_option(){
	case $OPTION in
				# If selected "Add user" go to function add_user
				1)	add_user
					;;
				# If selected "Edit user" go to function select_user
					# If user selected
				2)	if $(select_user) ;
						then
							# Selection menu
							choice=$(
								whiptail --title "$PREFIX$USER" --notags --cancel-button "Quit" --menu  "Select option:" 10 0 0 "$IDENT" "<< Back" 1 "Delete user" \
																		2 "Change password" \
																		3 "Add mailbox" \
																		4 "Delete mailbox" \
																		5 "Add alias" \
																		6 "Remove alias" 3>&1 1>&2 2>&3
									)
							case $choice in
									# If selected "Delete user" go to function r'emove_user'
									1)		remove_user
											;;
									# If selected "Change Password" go to function 'change_password'
									2) 		change_password
											;;
									# If selected "Add mailbox" go to function 'add_mailbox'
									3)		add_mailbox
											;;
									# If selected "Delete mailbox" go to function 'select_mailboxes'
									4)		select_mailboxes
											;;
									# If selected "Add alias" go to function 'add_alias'
									5)		add_alias
											;;
									# If selected "List alias" go to function 'list_aliases'
									6)		list_aliases
											;;
									"$IDENT")	declare -g EXIT_CODE=1
											;;
									*) 		declare -g EXIT_CODE=900
											;;
							esac
						else
							declare -g EXIT_CODE=1

					fi
					;;
	esac
}

# Select a user to edit
select_user() {
	# Load useres
	get_users
	usr=""
	cnt=0
	values=()
	# Load all users and counter into array 	
	for x in "${ARRUSERS[@]}"
		do
			let "cnt+=1"
			
			values+=("$cnt" "$x")	
		done

	if [ "${#ARRUSERS[@]}" -eq 0 ];
		then
			x=$(whiptail --msgbox "No users found!" 10 0 3>&1 1>&2 2>&3)
			echo false
		else
			# Whiptail - Selection menu
			choice=$(whiptail --title "Test" --notags --cancel-button "Quit" --menu  "Select User:" 10 0 0 "$IDENT" "<< Back" "${values[@]}" 3>&1 1>&2 2>&3) 
			# If not canceled	
			if [ "$choice" != "" ];
				then
					if [ "$choice" == "$IDENT" ];
						then
							echo false
						else
							# Set global var value to the selected username with domain
							declare -g USER=${values[$choice + $choice - 1]}
							# Set global var value to the selected username without domain
							declare -g USER_BLANK=$(echo $USER | awk '{split($0,a,"@"); print a[1]}')
							# Set global var MAILDIR_PATH to users individual Mail directory
							declare -g MAILDIR_PATH="${MAILDIR_PATH}$DOMAIN/$USER_BLANK"
							echo true
					fi
				else
					#Set exit code 
					exit
			fi
	fi
}

# Check if alias exists
check_alias(){
	# Array of all aliases
	ARRALIASES=($(awk "/'$DOMAIN'/ {print $1}" $ALIAS_FILE))
	# Looping through the alias array
	# echo false if alias exist in file and true if not
	for alias in ARRALIASES;
		do
			if [ "$alias" == "$1@$domain" ]; 
				then
					echo false
				else
					echo true
			fi
		done
}

# Adds an alias to the alias database
add_alias(){
	# Whiptail - Inputbox
	ALIAS=$(whiptail --inputbox "New Alias:" 10 30 3>&1 1>&2 2>&3)
	# If not canceled
	if [ "$ALIAS" != "" ]; 
		then
			# If alias doesn't exist in database
			if $(check_alias $ALIAS) ;
				then
					# Print alias into file
					echo "$ALIAS@$DOMAIN $USER" >> $ALIAS_FILE
					# Map alias into db file
					postmap $ALIAS_FILE
					# Reload postfix service
					postfix reload
				else
					# Whiptail - Infobox
					whiptail --msgbox "Aliasess already exists!" 10 30
					# Set exit code
					declare -g EXIT_CODE=2

	fi
		else
			# Set exit code
			declare -g EXIT_CODE=2
	fi
}

# List all aliases to delete
list_aliases(){
	# Get all aliases from aliases file
	aliases=$(grep "$USER" $ALIAS_FILE | awk -F " " '{print $1}')
	# Creates an array
	ARRALIASES=($aliases)

	# If array is empty
	if [ "${#ARRALIASES[@]}" -eq 0 ];
		then
			whiptail --msgbox "No Aliases defined!" 10 30	
			# Set exit code
			declare -g EXIT_CODE=2
		else
			# Enable nullglob shell option
			shopt -s nullglob
			cnt=0
			values=()
			# Insert all Aliases into array to dispay the selection menu
			for x in "${ARRALIASES[@]}"
				do
					let "cnt+=1"	
					# Insert into array
					values+=("$cnt" "$x")	
				done

			# Select alias from selection menu
			ANS="$(whiptail --title "$USER" --notags --cancel-button "Quit" --menu  "Select Alias:" 20 0 0 "$IDENT" "<< Back" "${values[@]}" 3>&1 1>&2 2>&3)"

			# If not canceled
			if [ "$ANS" != "" ]; 
				then 

					if [ $ANS == 0 ];
						then
							declare -g EXIT_CODE=2
						else
							# Confirm action
							ANS="$(whiptail --yesno "Delete alias ${values[$ANS + $ANS - 1]} ?" 0 0 3>&1 1>&2 2>&3; echo $?)"
							# If not canceled
							if [ $ANS == 0 ];
								then
									# Remove alias from alias file
									sed -i "/${values[$ANS + $ANS - 1]} $USER/d" "$ALIAS_FILE"
									# Create new alias database
									postmap "$ALIAS_FILE"
									whiptail --msgbox "Alias successfully deleted!" 10 20
								else
									# Set exit code
									declare -g EXIT_CODE=2
							fi
					fi
				else
					# Set exit code
					declare -g EXIT_CODE=900
			fi
	fi	
}

# Removes all aliases from a user
remove_aliases(){
	# Get all aliases from aliases file

 	aliases=$(grep "$USER" "$ALIAS_FILE" | awk -F " " '{print $1}')
 	# Creates an array
 	ARRALIASES=($aliases)

 	# If array isn' empty
 	if [ ! "${#ARRALIASES[@]}" -eq 0 ];
 	 	then
 	 		# Loop through aliases array
 	 		for x in "${ARRALIASE[@]}"
 	 			do
 	 				# Remove alias from aliases file
 	 				sed -i "/$x $USER/d" "$ALIAS_FILE"
 	 				# Create new alias database
					postmap "$ALIAS_FILE"
 	 			done
 	fi

}

# Check if mailbox exist
check_mailbox(){
	# If mailbox directory exists
	if [ -d "$MAILDIR_PATH/Maildir/.$1" ]; 
		then 
			echo true
		else
			echo false
	fi
}	

# Adds an mailbox to a user
add_mailbox(){
	# Get name of new mailbox 
	MBOX=$(whiptail --inputbox "Mailbox name:" 10 30 3>&1 1>&2 2>&3)

	# If not canceled
	if [ "$MBOX" != "" ]; 
		then
			bool=$(check_mailbox "$MBOX")
			# If mailbox doesn't exists
			if [ "$bool" = false ];
				then 
					# Create Mailbox
					doveadm mailbox create -s -u "$USER" "$MBOX"
					# Notification
					whiptail --msgbox "Maibox successfully created!" 10 30	
				else
					whiptail --msgbox "Maibox already exist!" 10 30	
					exit
			fi
		else
			# Whiptail - Ask again
			answer=$(whiptail --yesno "Are you sure?" 0 0 3>&1 1>&2 2>&3; echo $?)
#			 If clicked yes, exit
			if [ $answer == 0 ]; 
				then
					#user_edit_option
					declare -g EXIT_CODE=2
			fi
	fi
}

# List all mailboxes of a user
select_mailboxes() {
	shopt -s nullglob
	cnt=0
	values=()
	# Get all mailboxes of user in an array
	IFS=' ' read -r -a mboxes <<< "$(echo $(doveadm mailbox list -u $USER) | awk '{split($0,a,"\n "); print a[1]}')"
	# For all values in mboxes
	for x in "${mboxes[@]}"
		do
			let "cnt+=1"	
			# Insert into array
			values+=("$cnt" "$x")	
		done
	# If mailbox array is empty
	if [ "${#mboxes[@]}" -eq 0 ];
		then
			# Notification
			whiptail --msgbox "No mailboxes found!" 10 0 3>&1 1>&2 2>&3
			# Set exit code
			declare -g EXIT_CODE=2
		else
			# Whiptail - Selection menu
			choice=$(whiptail --title "$USER" --notags --cancel-button "Quit" --menu  "Select Mailbox:" 20 0 0 "$IDENT" "<< Back" "${values[@]}" 3>&1 1>&2 2>&3)

			# If not canceled
			if [ "$choice" != "" ];
				then
					if [ "$choice" == "$IDENT" ];
						then
							declare -g EXIT_CODE=2
						else	
							# Set mailbox to selected value
							mailbox=${values[$choice + $choice - 1]}
							# Delete mailbox
							remove_mailbox $mailbox
					fi
				else
					# Set exitcode
					declare -g EXIT_CODE=900
			fi
	fi
}

# Delete mailbox
remove_mailbox(){
	# Whiptail - Questionbox
	answer=$(whiptail --yesno "Delete Mailbox $1 ?" 0 0 3>&1 1>&2 2>&3; echo $?)
	# If clicked yes
	if [ $answer == 0 ];
		then
			# Delete mailbox
			doveadm mailbox delete -u "$USER" "$1"
			# Whiptail - Infobox
			whiptail --msgbox "Maibox successfully deleted!" 10 30	
		else
			#user_edit_option
			declare -g EXIT_CODE=2
	fi
}

# Change password of an existing user
change_password(){
	# Create new password
	pw=$(new_password)
	# If password entry wasn't canceled	
	if [ "$pw" != "" ]; 
		then
			# Remove old user entry in passwd file
			sed -i "/$USER/d" $PASSWD_FILE
			# Insert new user entry in passwd file
			echo "$USER:$pw::::::" >> $PASSWD_FILE
		else
			echo ""
	
	fi
}

# Create password for new users
new_password(){
	# User input
	PWD="$(whiptail --passwordbox --clear "New Password:" 10 100 3>&1 1>&2 2>&3)"

	# If password entry wasn't canceled
	if [ "$PWD" != "" ];
		then
			# Confirm input
			PWD_CHECK="$(whiptail --passwordbox --clear "Confirm password:" 10 100 3>&1 1>&2 2>&3)"
			# If password confirmed correctly
			if [ "$PWD" != "$PWD_CHECK" ]; 
				then
					echo ""
				else
					# echo / return new SSHA256 password
					echo "$(doveadm pw -s SSHA256 -p $PWD)"
			fi	
		else
			# Set exit code
			declare -g EXIT_CODE=1
	fi
}

# Edit configuration files 
edit_file(){
	if [ -f "$1" ];
		then
			vim "$1"
			declare -g EXIT_CODE=1
		else
			x=$(whiptail --msgbox "File does not exist!" 10 0)
	fi

}

# Postfix configuration menu
postfix_menu(){
	if [ "$1" -eq 0 ]; 
		then
			# Set exit code
			declare -g EXIT_CODE=5
			# Selection menu
			choice=$(whiptail --title "Mailadmin - Postfix" --notags --cancel-button "Quit" --menu  "Select option:" 10 0 0 "$IDENT" "<< Back" 1 "Edit configuration" \
																		2 "Start Postfix" \
																		3 "Stop Postfix" \
																		4 "Reload Postfix" \
																		5 "Status" \
																		6 "View logfile" 3>&1 1>&2 2>&3
			)
		else
			choice=$1
	fi

	case $choice in
				# Selection menu for config files
			1) choice2=$(whiptail --title "Mailadmin - Postfix menu" --notags --cancel-button "Quit" --menu  "Select config file:" 10 0 0 "$IDENT" "<< Back" 1 "main.cf" \
													2 "master.cf" 3>&1 1>&2 2>&3
						)
				case $choice2 in
						# Edit main.cf with chosen editor
						1) edit_file "${POSTFIX_PATH}main.cf"
							;;
						# Edit master.cf with chosen eidtor
						2) edit_file "${POSTFIX_PATH}master.cf"
							;;
						"$IDENT") declare -g EXIT_CODE=0
						# Set exit code
							;;
						*) declare -g EXIT_CODE=900
							;;
				esac
				;;
				# Start postfix service
			2) service postfix start 2>/dev/null
				# Notification		
				whiptail --msgbox "Postfix has been started!" 10 10 3>&1 1>&2 2>&3
				;;
				# Stop postfix service
			3) service postfix stop 2>/dev/null
				# Notification
				whiptail --msgbox "Postfix has been started!" 10 10 3>&1 1>&2 2>&3
				;;
				# Reload postfix seriver
			2) service postfix reload 2>/dev/null
				# Notification		
				whiptail --msgbox "Postfix has been reloaded!" 10 10 3>&1 1>&2 2>&3
				;;
				# Show status of postfix service
			5) whiptail --msgbox "$(service postfix status)" 10 0 3>&1 1>&2 2>&3
				;;
				# Show latest log entries
			6) whiptail --msgbox "$(tail /var/log/maillog)" 10 0 3>&1 1>&2 2>&3
				;;
			"$IDENT") declare -g EXIT_CODE=0
				;;
				# Set exit code
			*) declare -g EXIT_CODE=900
				;;
	esac	
}

# Dovecot configuration menu
dovecot_menu(){
	if [ "$1" -eq 0 ];
		then
			# Set exit code
			declare -g EXIT_CODE=4
			# Selection menu
			choice=$(whiptail --title "Mailadmin - Dovecot" --notags --cancel-button "Quit" --menu  "Select option:" 10 0 0 "$IDENT" "<< Back" 1 "Edit configuration" \
																		2 "Start Dovecot" \
																		3 "Stop Dovecot" \
																		4 "Reload Dovecot" \
																		5 "Status" \
																		6 "View logfile" 3>&1 1>&2 2>&3
			)
		else
			choice=$1
	fi

	case $choice in
				# Array of configuration files
			1) 	arr=("${DOVECOT_PATH}dovecot.conf")
				arr+=("$DOVECOT_PATH"conf.d/*)	
				# Counter			
				cnt=0
				values=()
				# Load all config files from array into other array with counter
				for x in "${arr[@]}"
					do
						let "cnt+=1"	
						# Insert into array
						values+=("$cnt" "$x")	
					done
				# Selection menu
				choice2=$(whiptail --title "Mailadmin - Dovecot menu" --cancel-button "Quit" --menu  "Select config file:" 10 0 0 "$IDENT" "<< Back" "${values[@]}" 3>&1 1>&2 2>&3
						)
				# If not canceled
				if [ "$choice2" != "" ];
					then
						if [ "$choice2" == "$IDENT" ];
							then
								declare -g EXIT_CODE=0
							else
								# Edit config selected file
								edit_file "${values[$choice2 + $choice2 - 1]}"
						fi
					else
						# Set exit code
						declare -g EXIT_CODE=0
				fi 
				;;
				# Start dovecot service
			2) service dovecot start 2>/dev/null
				# Notification
				whiptail --msgbox "Dovecot has been started!" 10 10 3>&1 1>&2 2>&3
				;;
				# Stop dovecot service
			3) service dovecot stop 2>/dev/null
				# Notification
				whiptail --msgbox "Dovecot has been started!" 10 10 3>&1 1>&2 2>&3
				;;
				# Reload dovecot service
			2) service dovecot reload 2>/dev/null
				# Notification
				whiptail --msgbox "Dovecot has been relaoded!" 10 10 3>&1 1>&2 2>&3
				;;
				# View status of dovecot service
			5) whiptail --msgbox "$(service dovecot status)" 10 0 3>&1 1>&2 2>&3
				;;
				# View logfiles
			6) 	log=$(whiptail --title "Mailadmin - Dovecot menu"  --menu  \
						"Select log file:" 10 0 0 1 "dovecot.log" 2 "dovecot-info.log" "$IDENT" "<< Back" 3>&1 1>&2 2>&3
					)
				case $log in
					1) whiptail --msgbox "$(tail /var/log/dovecot.log)" 10 0 3>&1 1>&2 2>&3
						;;
					2) whiptail --msgbox "$(tail /var/log/dovecot-info.log)" 10 0 3>&1 1>&2 2>&3
						;;
					"$IDENT") declare -g EXIT_CODE=0
						;;
					*) exit
				esac
				;;
			"$IDENT") declare -g EXIT_CODE=0
				;;
				# Set exit code
			*) declare -g EXIT_CODE=900
				;;
	esac	
}

load_domains(){
	T=($(cat /etc/dovecot/passwd | cut -d: -f1 | cut -d@ -f2 | sort | uniq))
	DOMAINS=()
	for i in `seq 0 $(let x=${#T[@]}-1; echo $x)`;
        do
        		var="${T[$i]}"
                DOMAINS+=( "$var" "  >>  $var" )
        done  

}

# Main menu of script
main_menu(){

	# Selection menu
	choice=$(whiptail --title "Mailadmin - Administration interface" --notags --cancel-button "Quit" --menu  "Select option:" 10 0 0 1 "Administration" \
																"${DOMAINS[@]}"\
																"?" "" \
																2 "Postfix" \
																3 "  >>  Edit configuration" \
																4 "  >>  Start Service" \
																5 "  >>  Stop Service" \
																6 "  >>  Reload Service" \
																7 "  >>  Status" \
																8 "  >>  View logfile" \
																"?" "" \
																9 "Dovecot" \
																10 "  >>  Edit configuration" \
																11 "  >>  Start Service" \
																12 "  >>  Stop Service" \
																13 "  >>  Reload Service" \
																14 "  >>  Status" \
																15 "  >>  View logfile" 3>&1 1>&2 2>&3
			)

		case $choice in
				# Go to 'select_domain'
				1) select_domain ""
					;;
				# Go to 'postfix_menu'
				2) postfix_menu 0
					;;
				3) postfix_menu 1
					;;
				4) postfix_menu 2
					;;
				5) postfix_menu 3
					;;
				6) postfix_menu 4
					;;
				7) postfix_menu 5
					;;
				8) postfix_menu 6
					;;
				9) dovecot_menu 0
					;;
				10) dovecot_menu 1
					;;
				11) dovecot_menu 2
					;;
				12) dovecot_menu 3
					;;
				13) dovecot_menu 4
					;;
				14) dovecot_menu 5
					;;
				15) dovecot_menu 6
					;;
				"?") declare -g EXIT_CODE=0
					;;
				# Set exit code
				*) 
					if [ "$choice" != "" ];
						then
							select_domain "$choice"
						else
							declare -g EXIT_CODE=900
					fi
					;;

		esac
}

# List all available domains
select_domain() {
	if [ "$1" == "" ];
		then
			# Selection menu
			choice=$(whiptail --title "Dovecot User Administration" --notags --cancel-button "Quit" --menu  "Select Domain:" 10 0 0 "$IDENT" "<< Back" "${DOMAINS[@]}" 3>&1 1>&2 2>&3)
		else
			choice=$1
	fi
	# If not canceled
	if [ "$choice" != "" ]; 
		then
			if [ "$choice" = "$IDENT" ]; 
				then
					declare -g EXIT_CODE=0
				else
					# Set global var for the selected domain
					declare -g DOMAIN="$choice"
					# Go to user_option
					user_option
			fi
		else
			# Set exit code
			declare -g EXIT_CODE=900
	fi
}

check_files
load_domains

# Navigate to a function via exit code
while true; do	
	case $EXIT_CODE in
		0) main_menu
			;;
		1) user_option
			;;
		2) user_edit_option
			;;
		3) select_domain
			;;
		4) dovecot_menu 0
			;;
		5) postfix_menu 0
			;;
		900) exit
			;;	
	esac
done