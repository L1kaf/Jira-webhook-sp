#!/bin/bash

. ./.env

ISSUE_KEY=$(echo "$QUERY_STRING" | sed -n 's/.*issue=\([^&]*\).*/\1/p')
echo "Обрабатывается задача: $ISSUE_KEY" >> $LOG_FILE

# Проверяем, есть ли родитель
PARENT_KEY=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY?fields=parent" | jq -r '.fields.parent.key')

if [ "$PARENT_KEY" == "null" ] || [ -z "$PARENT_KEY" ]; then
  echo "Задача $ISSUE_KEY не является подзадачей" >> $LOG_FILE
  exit 0
fi

echo "Родительская задача: $PARENT_KEY" >> $LOG_FILE

# Получаем все подзадачи родителя с полем customfield_10200
SUBTASKS=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/search?jql=parent=$PARENT_KEY&fields=customfield_10200" \
  | jq -c '.issues[] | {key: .key, sp: .fields.customfield_10200}')

# Суммируем SP
TOTAL_SP=0
for SUB in $SUBTASKS; do
  SP=$(echo "$SUB" | jq -r '.sp')
  if [[ "$SP" != "null" ]]; then
    TOTAL_SP=$(echo "$TOTAL_SP + $SP" | bc)
  fi
done

echo "Сумма SP подзадач: $TOTAL_SP" >> $LOG_FILE

# Получаем текущий SP родителя
CURRENT_SP=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/issue/$PARENT_KEY?fields=customfield_10200" \
  | jq -r ".fields.customfield_10200")

echo "Текущее значение SP родителя: $CURRENT_SP" >> $LOG_FILE

# Если SP совпадает — ничего не делаем
if [[ "$CURRENT_SP" == "$TOTAL_SP" ]]; then
  echo "SP уже актуальны, изменений не требуется" >> $LOG_FILE
  exit 0
fi

# Обновляем SP родителя
UPDATE_JSON=$(jq -n --argjson sp $TOTAL_SP '{fields: {"customfield_10200": $sp}}')

curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -X PUT \
  --data "$UPDATE_JSON" \
  "$JIRA_URL/rest/api/2/issue/$PARENT_KEY" > /dev/null

echo "Обновлено значение SP родителя $PARENT_KEY: $TOTAL_SP" >> $LOG_FILE


# HTTP-ответ для nginx/fcgiwrap
echo -e "Status: 200 OK\r"
echo -e "Content-Type: text/plain\r"
echo -e "\r"
echo -e "Webhook received and logged."
