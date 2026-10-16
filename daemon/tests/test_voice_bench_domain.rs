use astral_plasma::domain::voice::{calculate_cer, calculate_wer, normalize_text_for_eval};

#[test]
fn test_normalize_text_for_eval() {
    assert_eq!(normalize_text_for_eval("Front, Center!"), "front center");
    assert_eq!(normalize_text_for_eval("你好，世界！"), "你好世界");
    assert_eq!(normalize_text_for_eval("API 性能"), "api 性能");
}

#[test]
fn test_calculate_wer() {
    assert_eq!(calculate_wer("front center", "front center"), 0.0);
    assert_eq!(calculate_wer("front", "front center"), 0.5);
    assert_eq!(calculate_wer("front middle", "front center"), 0.5);
    assert_eq!(calculate_wer("completely different", "front center"), 1.0);
}

#[test]
fn test_calculate_cer() {
    assert_eq!(calculate_cer("你好世界", "你好世界"), 0.0);
    assert_eq!(calculate_cer("你好", "你好世界"), 0.5);
    assert_eq!(calculate_cer("你好地球", "你好世界"), 0.5);
}
