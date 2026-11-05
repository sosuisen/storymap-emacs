//! Read a story map outline from standard input, and write the map image to standard output.

use std::env;
use std::io::{self, Read, Write};
use std::process::ExitCode;

use storymap::image::{ImageOptions, render_png, render_svg};

const USAGE: &str = "usage: story-mapping-render svg | story-mapping-render png [SCALE]";

/// The image that the caller asks for
#[derive(Debug, PartialEq)]
enum Request {
    Svg,
    /// `scale` is a positive finite number, because `render_png` panics on any other value
    Png {
        scale: f32,
    },
}

fn parse_args(args: &[String]) -> Result<Request, String> {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        ["svg"] => Ok(Request::Svg),
        ["png"] => Ok(Request::Png { scale: 1.0 }),
        ["png", scale] => parse_scale(scale).map(|scale| Request::Png { scale }),
        _ => Err(USAGE.to_string()),
    }
}

fn parse_scale(text: &str) -> Result<f32, String> {
    match text.parse::<f32>() {
        Ok(scale) if scale.is_finite() && scale > 0.0 => Ok(scale),
        _ => Err(format!("the scale must be a positive number: {text}")),
    }
}

fn render(request: &Request, outline: &str) -> Vec<u8> {
    let map = storymap::parse(outline);
    match *request {
        Request::Svg => render_svg(&map, &ImageOptions::default()).into_bytes(),
        Request::Png { scale } => render_png(
            &map,
            &ImageOptions {
                scale,
                ..ImageOptions::default()
            },
        ),
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    let request = parse_args(&args)?;
    let mut outline = String::new();
    io::stdin()
        .read_to_string(&mut outline)
        .map_err(|error| format!("cannot read the outline: {error}"))?;
    io::stdout()
        .write_all(&render(&request, &outline))
        .map_err(|error| format!("cannot write the image: {error}"))
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(ToString::to_string).collect()
    }

    /// `svg`の指定はSVGの要求である
    #[test]
    fn svg_argument_requests_svg() {
        assert_eq!(parse_args(&args(&["svg"])), Ok(Request::Svg));
    }

    /// 倍率のない`png`の指定は等倍のPNGの要求である
    #[test]
    fn png_argument_without_scale_requests_scale_one() {
        assert_eq!(parse_args(&args(&["png"])), Ok(Request::Png { scale: 1.0 }));
    }

    /// `png`の倍率は要求に反映される
    #[test]
    fn png_argument_with_scale_requests_that_scale() {
        assert_eq!(
            parse_args(&args(&["png", "1.5"])),
            Ok(Request::Png { scale: 1.5 })
        );
    }

    /// 正の有限の数でない倍率は拒否される
    #[test]
    fn scale_that_is_not_positive_and_finite_is_rejected() {
        for scale in ["0", "-1", "inf", "NaN", "large"] {
            assert!(parse_args(&args(&["png", scale])).is_err(), "{scale}");
        }
    }

    /// 形式のない指定、未知の形式、余分な引数は拒否される
    #[test]
    fn unknown_arguments_are_rejected() {
        for values in [&[][..], &["pdf"], &["svg", "2"], &["png", "2", "3"]] {
            assert!(parse_args(&args(values)).is_err(), "{values:?}");
        }
    }
}
