with open('lib/features/local_test/history_screen.dart', 'r') as f:
    text = f.read()

text = text.replace('AppColors.ink12', 'AppColors.ink2')
text = text.replace('AppColors.ink13', 'AppColors.ink3')

with open('lib/features/local_test/history_screen.dart', 'w') as f:
    f.write(text)
