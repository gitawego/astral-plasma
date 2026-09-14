pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string temp: "18°C"
    property string condition: "Clear"
    property string weatherIcon: "weather_clear"
    property string city: ""

    readonly property string conditionIcon: weatherIcon
    readonly property string tempString: temp

    Process {
        id: fetchWeather
        command: ["curl", "-s", "wttr.in/?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text.trim());
                    if (data.current_condition && data.current_condition.length > 0) {
                        const cur = data.current_condition[0];
                        root.temp = cur.temp_C + "°C";
                        if (cur.weatherDesc && cur.weatherDesc.length > 0) {
                            root.condition = cur.weatherDesc[0].value;
                        }
                        const descLower = root.condition.toLowerCase();
                        if (descLower.includes("rain") || descLower.includes("drizzle")) {
                            root.weatherIcon = "weather_rain";
                        } else if (descLower.includes("cloud") || descLower.includes("overcast")) {
                            root.weatherIcon = "weather_cloudy";
                        } else {
                            root.weatherIcon = "weather_clear";
                        }
                    }
                    if (data.nearest_area && data.nearest_area.length > 0) {
                        const area = data.nearest_area[0];
                        if (area.areaName && area.areaName.length > 0) {
                            root.city = area.areaName[0].value;
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 1800000 // 30 minutes
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!fetchWeather.running) fetchWeather.running = true;
        }
    }
}
