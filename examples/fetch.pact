// fetch.pact — Effects, handlers, testing
//
// Demonstrates: effect declarations, handlers, with blocks,
//               mock handlers for testing, DI via effects

type WeatherError {
    NetworkFailed(msg: Str)
    ParseFailed(msg: Str)
}

type Forecast {
    city: Str
    temp_c: Float
    summary: Str
}

/// Fetch weather data for a city.
fn fetch_forecast(city: Str) -> Result[Forecast, WeatherError] ! Net.Connect, IO.Log {
    io.log("Fetching weather for {city}")
    let url = "https://api.weather.example/v1/forecast?city={city}"
    let response = net.get(url)?
    parse_forecast(city, response.body())
}

/// Parse a JSON response into a Forecast.
fn parse_forecast(city: Str, body: Str) -> Result[Forecast, WeatherError] {
    let json = json.parse(body) ?? return Err(WeatherError.ParseFailed("invalid JSON"))
    Ok(Forecast {
        city: city
        temp_c: json.get("temp_c")?.as_float() ?? 0.0
        summary: json.get("summary")?.as_str() ?? "Unknown"
    })
}

/// Fetch multiple cities and print results.
fn fetch_and_print(cities: List[Str]) ! Net.Connect, IO {
    let mut count = 0
    for city in cities {
        match fetch_forecast(city) {
            Ok(f) => io.println("{f.city}: {f.temp_c}°C — {f.summary}")
            Err(e) => io.println("Failed for {city}: {e}")
        }
        count = count + 1
    }
    io.println("Fetched {count} cities.")
}

/// Create a mock Net handler that returns canned responses.
fn mock_net(responses: Map[Str, Str]) -> Handler[Net.Connect] {
    handler Net.Connect {
        fn get(url: Str) -> Result[Response, NetError] {
            match responses.get(url) {
                Some(body) => Ok(Response.new(200, body))
                None => Err(NetError.ConnectionRefused("mock: no response for {url}"))
            }
        }
    }
}

fn main() {
    let cities = ["London", "Tokyo", "Portland"]
    fetch_and_print(cities)
}

test "fetch_forecast with mock" {
    let body = "\{\"temp_c\": 18.5, \"summary\": \"Partly cloudy\"\}"
    let responses = Map.of([
        ("https://api.weather.example/v1/forecast?city=London", body)
    ])

    with mock_net(responses), capture_log([]) {
        let result = fetch_forecast("London")
        assert(result.is_ok())
        let forecast = result.unwrap()
        assert_eq(forecast.city, "London")
        assert_eq(forecast.temp_c, 18.5)
        assert_eq(forecast.summary, "Partly cloudy")
    }
}

test "fetch_forecast network failure" {
    let responses = Map.of([])

    with mock_net(responses), capture_log([]) {
        let result = fetch_forecast("Atlantis")
        assert(result.is_err())
    }
}
