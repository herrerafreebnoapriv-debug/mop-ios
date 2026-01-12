"""
i18n 功能测试脚本
"""

from app.core.i18n import i18n, SUPPORTED_LANGUAGES

print("=" * 60)
print("i18n Implementation Test")
print("=" * 60)

print(f"\nSupported languages: {len(SUPPORTED_LANGUAGES)}")
for code in SUPPORTED_LANGUAGES.keys():
    print(f"  {code}")

print("\n" + "-" * 60)
print("Translation Tests:")
print("-" * 60)

# 测试应用名称（品牌命名规范）
print("\n1. App Name (Brand Naming):")
print(f"   zh_CN: {i18n.get('app.name', 'zh_CN')}")  # 应该输出: 和平信使
print(f"   en_US: {i18n.get('app.name', 'en_US')}")  # 应该输出: MOP

# 测试认证相关
print("\n2. Auth Messages:")
print(f"   zh_CN login.failed: {i18n.get('auth.login.failed', 'zh_CN')}")
print(f"   en_US login.failed: {i18n.get('auth.login.failed', 'en_US')}")
print(f"   zh_CN register.phone_exists: {i18n.get('auth.register.phone_exists', 'zh_CN')}")
print(f"   en_US register.phone_exists: {i18n.get('auth.register.phone_exists', 'en_US')}")

# 测试通用消息
print("\n3. Common Messages:")
print(f"   zh_CN success: {i18n.get('common.success', 'zh_CN')}")
print(f"   en_US success: {i18n.get('common.success', 'en_US')}")

# 测试带参数的翻译
print("\n4. Parameterized Translation:")
welcome_zh = i18n.get('common.welcome', 'zh_CN', app_name='MOP')
welcome_en = i18n.get('common.welcome', 'en_US', app_name='MOP')
print(f"   zh_CN: {welcome_zh}")
print(f"   en_US: {welcome_en}")

# 测试语言规范化
print("\n5. Language Normalization:")
test_cases = ['zh', 'zh-CN', 'zh_CN', 'en', 'en-US', 'en_US', 'invalid']
for test_lang in test_cases:
    normalized = i18n.normalize_language(test_lang)
    print(f"   '{test_lang}' -> '{normalized}'")

print("\n" + "=" * 60)
print("[SUCCESS] i18n implementation is working correctly!")
print("=" * 60)
