type Celsius {
    value: Float
}

type Fahrenheit {
    value: Float
}

impl From[Celsius] for Fahrenheit {
    fn from(c: Celsius) -> Self {
        Fahrenheit { value: c.value * 1.8 + 32.0 }
    }
}

test "Celsius to Fahrenheit via into() - boiling point" {
    let c = Celsius { value: 100.0 }
    let f: Fahrenheit = c.into()
    assert_eq(f.value, 212.0)
}

test "Celsius to Fahrenheit via into() - freezing point" {
    let c2 = Celsius { value: 0.0 }
    let f2: Fahrenheit = c2.into()
    assert_eq(f2.value, 32.0)
}
