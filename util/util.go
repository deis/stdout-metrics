package util

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	//[2016-05-06T20:04:23+00:00]
	longForm = "[2006-01-02T15:04:05-07:00]"
)

func fromKubernetes(json map[string]interface{}) bool {
	return json["kubernetes"] != nil
}

// FromContainer checks that the log message is from a given container
func FromContainer(json map[string]interface{}, pattern string) bool {
	if !fromKubernetes(json) {
		return false
	}

	containerName := json["kubernetes"].(map[string]interface{})["container_name"].(string)
	matched, _ := regexp.MatchString(pattern, containerName)
	return matched
}

//ParseMessage takes a string and returns a map
func ParseMessage(message string) (map[string]interface{}, error) {
	curlyIndex := strings.Index(message, "{")
	if curlyIndex > -1 {
		message = message[curlyIndex:]
		var messageJSON map[string]interface{}
		err := json.Unmarshal([]byte(message), &messageJSON)
		if err == nil {
			return messageJSON, nil
		}
		return nil, err
	}
	return nil, fmt.Errorf("Not a valid JSON message: %s", message)
}

//GetHost returns the host value from the kubernetes submap
func GetHost(json map[string]interface{}) string {
	return json["kubernetes"].(map[string]interface{})["host"].(string)
}

//ParseNginxLog returns map of the parsed nginx log
func ParseNginxLog(message string) (map[string]interface{}, error) {
	parsedMessage := make(map[string]interface{})
	splitMessage := strings.Split(message, " - ")
	if len(splitMessage) > 1 {
		timestamp, err := toTime(splitMessage[0])
		if err != nil {
			return nil, err
		}

		bytesSent, err := strconv.Atoi(strings.TrimSpace(splitMessage[6]))
		if err != nil {
			return nil, err
		}

		responseTime, err := strconv.ParseFloat(strings.TrimSpace(splitMessage[12]), 64)
		if err != nil {
			return nil, err
		}

		requestTime, err := strconv.ParseFloat(strings.TrimSpace(splitMessage[13]), 64)
		if err != nil {
			return nil, err
		}

		parsedMessage["time"] = timestamp
		parsedMessage["app"] = strings.TrimSpace(splitMessage[1])
		parsedMessage["status_code"] = strings.TrimSpace(splitMessage[4])
		parsedMessage["bytes_sent"] = bytesSent
		parsedMessage["response_time"] = responseTime
		parsedMessage["request_time"] = requestTime
		return parsedMessage, nil
	}
	return nil, fmt.Errorf("Invalid nginx log message: %s", message)
}

//Turn this [2016-05-06T20:04:23+00:00] into time object
func toTime(date string) (time.Time, error) {
	t, err := time.Parse(longForm, date)
	if err != nil {
		return time.Now(), err
	}
	return t, nil
}
