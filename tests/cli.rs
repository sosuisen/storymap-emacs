use std::io::Write;
use std::process::{Command, Output, Stdio};

const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";

fn run(args: &[&str], stdin: &[u8]) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_story-mapping-render"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the program starts");
    child
        .stdin
        .take()
        .expect("stdin is piped")
        .write_all(stdin)
        .expect("the program reads the outline");
    child.wait_with_output().expect("the program ends")
}

// The width in the IHDR chunk, which directly follows the signature and the chunk header
fn png_width(png: &[u8]) -> u32 {
    u32::from_be_bytes(png[16..20].try_into().expect("the slice has 4 bytes"))
}

/// `svg`は、アウトラインの本文を含むSVGを標準出力へ書く
#[test]
fn svg_writes_document_with_the_outline_text() {
    let output = run(&["svg"], "- 活動A\n  - Task A1\n".as_bytes());

    assert!(output.status.success());
    let svg = String::from_utf8(output.stdout).expect("the SVG is UTF-8");
    assert!(svg.starts_with("<svg"));
    assert!(svg.contains("活動A"));
    assert!(svg.contains("Task A1"));
}

/// `png`は、PNGを標準出力へ書く
#[test]
fn png_writes_png_image() {
    let output = run(&["png"], b"- Activity A\n");

    assert!(output.status.success());
    assert!(output.stdout.starts_with(PNG_SIGNATURE));
}

/// `png`の倍率を2倍にすると、画像の幅は等倍の2倍前後になる
#[test]
fn png_scale_changes_the_image_width() {
    let outline = b"- Activity A\n";

    let one = png_width(&run(&["png", "1"], outline).stdout);
    let two = png_width(&run(&["png", "2"], outline).stdout);

    assert!(two.abs_diff(one * 2) <= 1, "{one} and {two}");
}

/// 空のアウトラインでも画像を書く
#[test]
fn empty_outline_writes_an_image() {
    let output = run(&["png"], b"");

    assert!(output.status.success());
    assert!(output.stdout.starts_with(PNG_SIGNATURE));
}

/// 不正な引数では、失敗で終わり、標準出力に何も書かず、理由を標準エラーへ書く
#[test]
fn wrong_argument_fails_with_a_message() {
    let output = run(&["pdf"], b"");

    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(!output.stderr.is_empty());
}

/// UTF-8でない入力では、失敗で終わる
#[test]
fn outline_that_is_not_utf8_fails() {
    let output = run(&["svg"], b"\xff\xfe");

    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
}
