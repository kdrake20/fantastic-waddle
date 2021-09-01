#!/usr/local/bin/bash

CURRENT_BRANCH="$(git branch --show-current)"

#Your working branch name must be the JIRA ticket number. For example: TELCODOCS-250
#JIRA_TICKET=$CURRENT_BRANCH

echo "Enter the JIRA ticket (e.g., TELCODOCS-250) [Enter]:"
read JIRA_TICKET

#The username and password is your JIRA username and password.
USERNAME=rhn-support-ktothill
PASSWORD="dS99fejLnWBv&47Iudm^"

#Ensure you are executing the script from within a git repository.
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Proceeding with creating a PR."
else
  echo "This is not a git repository. Please check your path syntax."
  exit
fi

#Make sure you are not on the main branch.
if [ $CURRENT_BRANCH == "main" ]; then
  echo "ERROR: You should only execute this script on a working branch."
  exit
fi

#Retrieve the summary and git pull request fields from JIRA.
JSON_QUERY=$(curl -u $USERNAME:$PASSWORD https://issues.redhat.com/rest/api/2/issue/$JIRA_TICKET?fields=summary,customfield_12310220)

#Get the JIRA summary/title as raw text.
SUMMARY=$(echo $JSON_QUERY | jq -r .fields.summary)

#Prompt for a git commit message.
echo "Enter a commit message followed by [Enter]: "
read ANSWER

#Build the PR body in a text file to ensure formatting works properly.
#==============
#Commit message
echo -e "$ANSWER\n" > tmp.txt

#Adds JIRA ticket to message.
echo -e "Fixes: $JIRA_TICKET\n" >> tmp.txt

#Adds URL to JIRA ticket as a backup if github method breaks again.
echo -e "See https://issues.redhat.com/browse/$JIRA_TICKET for additional details.\n" >> tmp.txt

#Adds a preview URL placeholder as a reminder.
echo -e "Preview URL:\n" >> tmp.txt

#Prompts for the release(s) pertinent to the PR. This helps those merging the PR.
echo "What release(s) is this PR for?"
read RELEASE
echo -e "For release(s): $RELEASE" >> tmp.txt

#Adds the user sign off.
echo -e "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" >> tmp.txt


#Create the PR and remove the temporary file.
#Note, the title -t is the JIRA ticket number followed by the JIRA ticket summary/title.
PR_URL=$(gh pr create  -t "$JIRA_TICKET: $SUMMARY" --body-file tmp.txt)
rm tmp.txt

#JIRA only supports a "set" operation on custom fields.
#The "add" method common to "comments" isn't supported. So you
#must get the git PRs field to determine if it has any contents.

#Get the length of the git PRs field from JIRA.
LENGTH=$(echo $JSON_QUERY | jq -r '.fields.customfield_12310220 | length')

if [ $LENGTH -gt 0 ];
then
  #Get the content of the git-repos field from JIRA.
  PR_URLS=$(echo $JSON_QUERY | jq -r .fields.customfield_12310220)
  #Add the PR_URL to the array.
  PR_URLS=$(echo $PR_URLS | jq --arg pr "$PR_URL" '. += [$pr]')
  #Strip the array syntax down to a simple string.
  PR_URLS=$(echo $PR_URLS | sed -E "s/ //g" | sed -En "s/\[//p" | sed -En "s/\]//p" | sed -E 's/"//g')
  #Add the string of URLs to set in the git PRs field in JIRA.
  PR_INPUT="{\"update\":{\"customfield_12310220\":[{\"set\":\"$PR_URLS\"}]}}"
else
  #If there are no pre-existing URLs, just add the new one to set in the git PRs field in JIRA.
  PR_INPUT="{\"update\":{\"customfield_12310220\":[{\"set\":\"$PR_URL\"}]}}"
fi

#Set the git PRs field in JIRA.
curl -D- -u $USERNAME:$PASSWORD -X PUT --data "$PR_INPUT" -H "Content-Type: application/json" https://issues.redhat.com/rest/api/2/issue/$JIRA_TICKET
