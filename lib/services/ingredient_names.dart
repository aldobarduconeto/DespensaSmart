/// Vocabulário usado tanto na busca quanto na comparação de ingredientes.
class IngredientNames {
  static const aliases = <String, String>{
    'tomatoes': 'tomato',
    'potatoes': 'potato',
    'leaves': 'leaf',
    'arroz': 'rice',
    'feijao': 'kidney beans',
    'frango': 'chicken',
    'peito de frango': 'chicken breast',
    'carne': 'beef',
    'carne bovina': 'beef',
    'carne moida': 'minced beef',
    'porco': 'pork',
    'peixe': 'fish',
    'atum': 'tuna',
    'ovo': 'egg',
    'ovos': 'egg',
    'leite': 'milk',
    'queijo': 'cheese',
    'manteiga': 'butter',
    'creme de leite': 'cream',
    'tomate': 'tomato',
    'tomates': 'tomato',
    'cebola': 'onion',
    'cebolas': 'onion',
    'alho': 'garlic',
    'batata': 'potato',
    'batatas': 'potato',
    'cenoura': 'carrot',
    'cenouras': 'carrot',
    'abobrinha': 'courgettes',
    'berinjela': 'aubergine',
    'brocolis': 'broccoli',
    'espinafre': 'spinach',
    'milho': 'sweetcorn',
    'ervilha': 'peas',
    'ervilhas': 'peas',
    'lentilha': 'lentils',
    'grao de bico': 'chickpeas',
    'pimentao': 'bell pepper',
    'cogumelo': 'mushrooms',
    'cogumelos': 'mushrooms',
    'macarrao': 'spaghetti',
    'farinha de trigo': 'plain flour',
    'farinha': 'flour',
    'acucar': 'sugar',
    'sal': 'salt',
    'azeite': 'olive oil',
    'oleo': 'vegetable oil',
    'pimenta': 'pepper',
    'pimenta do reino': 'black pepper',
    'limao': 'lemon',
    'laranja': 'orange',
    'banana': 'banana',
    'maca': 'apple',
    'aveia': 'oats',
    'pao': 'bread',
    'molho de tomate': 'tomato sauce',
    'salsa': 'parsley',
    'salsinha': 'parsley',
    'coentro': 'coriander',
    'manjericao': 'basil',
    'oregano': 'oregano',
    'chocolate': 'chocolate',
    'iogurte': 'yogurt',
  };

  static String normalize(String value) {
    var result = value.toLowerCase().trim();
    const accents = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    accents.forEach((a, b) => result = result.replaceAll(a, b));
    return result
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String canonical(String value) {
    final normalized = normalize(value);
    return aliases[normalized] ?? normalized;
  }

  static String matchKey(String value) => canonical(value)
      .split(' ')
      .map(
        (w) => w.endsWith('s') && !w.endsWith('ss')
            ? w.substring(0, w.length - 1)
            : w,
      )
      .join(' ');
  static bool matches(String a, String b) {
    final left = matchKey(a);
    return left.isNotEmpty && left == matchKey(b);
  }
}
