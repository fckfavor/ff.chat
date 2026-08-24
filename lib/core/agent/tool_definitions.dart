import '../storage/plugin_repository.dart';

/// OpenAI-compatible tool definitions — LLM'e "hangi fonksiyonlari cagirabilirsin" diye gonderilir.
///
/// Her preset icin ayni degil: OpenAI/DeepSeek tool calling'i destekler,
/// Anthropic/Gemini farkli format kullanir. MVP'de sadece OpenAI-compatible
/// preset'lerde bu tool'lar aktif olacak (BuiltinPresets.openAiCompatible).
class ToolDefinitions {
  ToolDefinitions._();

  /// Built-in tool listesi (const, degismez). Plugin'lar bunun UZERINE eklenir.
  static const List<Map<String, dynamic>> openAiTools = [
    {
      'type': 'function',
      'function': {
        'name': 'file_read',
        'description': 'Workspace icindeki bir dosyayi oku. Relative path ver (or: "main.dart", "lib/app.dart"). Binary degil text dosyalar icin.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Okunacak dosyanin workspace-relative yolu'},
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_write',
        'description': 'Workspace icine dosya yaz/olustur. Parent dizinler otomatik olusur. Var olan dosya uzerine yazar.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Yazilacak dosyanin yolu'},
            'content': {'type': 'string', 'description': 'Dosya icerigi'},
          },
          'required': ['path', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_list',
        'description': 'Bir dizinin icerigini listele. "." kok dizindir.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Listelenecek dizin yolu (default ".")'},
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_delete',
        'description': 'Dosya veya dizini sil (recursive). Kok dizin silinemez.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Silinecek yol'},
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'shell_exec',
        'description': 'Linux shell komutu calistir. Workspace kokunde calisir. Or: "ls -la", "cat file.txt", "mkdir -p src", "echo hello > test.txt", "python3 main.py". Guvenli olmayan komutlar engellenir.',
        'parameters': {
          'type': 'object',
          'properties': {
            'command': {'type': 'string', 'description': 'Calistirilacak shell komutu'},
            'workdir': {'type': 'string', 'description': 'Calisma dizini (workspace-relative, default ".")'},
          },
          'required': ['command'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_edit',
        'description': 'Var olan dosyada TEK bir unique substringi degistir. old_string dosya icinde tam olarak 1 kez gecmeli, 0 veya >1 ise hata doner. Kucuk duzeltmeler icin file_write yerine bunu kullan (token tasarrufu, diff preview).',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Duzenlenecek dosyanin yolu'},
            'old_string': {'type': 'string', 'description': 'Degistirilecek unique metin - dosyada tam 1 kez gecmeli'},
            'new_string': {'type': 'string', 'description': 'Yeni metin (bos string ise silme)'},
          },
          'required': ['path', 'old_string', 'new_string'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_glob',
        'description': 'Workspace icinde glob pattern ile dosya ara. Or: **/*.dart, lib/**/*.tsx, *.md. Recursive, shell gerektirmez.',
        'parameters': {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string', 'description': 'Glob pattern, or **/*.dart'},
            'path': {'type': 'string', 'description': 'Baslangic dizini, default "."'},
          },
          'required': ['pattern'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'file_grep',
        'description': 'Workspace dosyalarinda regex/keyword ara. Her eslesme file:line:preview seklinde doner. Shell grep yerine bunu kullan.',
        'parameters': {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string', 'description': 'Aranacak regex veya plain string'},
            'path': {'type': 'string', 'description': 'Baslangic dizini, default "."'},
            'glob': {'type': 'string', 'description': 'Sadece bu glob\'a uyan dosyalarda ara, or *.dart'},
          },
          'required': ['pattern'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'todo_write',
        'description': 'Karmasik gorevlerde plan listesi olustur/guncelle. Her todo: content, status(pending/in_progress/completed/cancelled), priority(high/medium/low). Plan degistikce cagir.',
        'parameters': {
          'type': 'object',
          'properties': {
            'todos': {
              'type': 'array',
              'description': 'Todo listesi',
              'items': {
                'type': 'object',
                'properties': {
                  'content': {'type': 'string', 'description': 'Yapilacak is'},
                  'status': {'type': 'string', 'enum': ['pending', 'in_progress', 'completed', 'cancelled'], 'description': 'Durum'},
                  'priority': {'type': 'string', 'enum': ['high', 'medium', 'low'], 'description': 'Oncelik'},
                },
                'required': ['content', 'status'],
              },
            },
          },
          'required': ['todos'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'dispatch_subtask',
        'description': 'Alt gorevi bagimsiz subagent\'a devret. Ana context sismeden arastirma/analiz yaptir, ozet dondur. Use for: codebase kesfi, dosya tarama, plan olusturma. Subagent derin dusunme (incele->dusun->plan->uygula) ile calisir.',
        'parameters': {
          'type': 'object',
          'properties': {
            'task': {'type': 'string', 'description': 'Subagent\'a verilecek gorev aciklamasi (detayli, or: "lib/ klasorunu tara, auth akisini incele, plan cikar")'},
            'context': {'type': 'string', 'description': 'Opsiyonel ek baglam (or: ilgili dosya yollari, onceki plan)'},
          },
          'required': ['task'],
        },
      },
    },
  ];

  /// System prompt'a eklenecek tool kullanim talimati.
  static const String toolSystemPromptAddendum = '''
Sen workspace'i olan bir AI agentsin. Asagidaki tool'lari kullanarak dosya okuyabilir, yazabilir, listeleyebilir ve shell komutu calistirabilirsin.

Calisma prensibin: ONCE INCELE -> DUSUN -> PLAN YAP -> UYGULA. Asla dusunmeden uygulamaya gecme.
Kurallar:
- Tool cagrisi gerektiginde SADECE tool_call yap, metin aciklamasi ekleme (aciklamayi tool sonrasinda yap).
- file_read/file_list ile kesfet, ARAMA icin shell_exec yerine file_glob (dosya adlari) ve file_grep (icerik) kullan.
- Yeni dosya veya tam uzerine yazma icin file_write, KUCUK duzeltme/parca degisiklik icin file_edit (old_string unique olmali) kullan.
- Karmasik gorevlerde (3+ adim) todo_write ile plan olustur, her adim oncesi in_progress isaretle, bitince completed yap.
- Arastirma/kesif icin dispatch_subtask kullan — ana context sismeden subagent'a devret, derin dusunme ile analiz ettir.
- Komutlar workspace icinde izole calisir, disari cikamaz.
- Her tool sonucundan sonra kullaniciya ne yaptigini kisa ozetle.
''';

  /// Subagent icin derin dusunme prompt'u — incele/dusun/plan/uygula + thinking block
  static const String subagentSystemPromptAddendum = '''
Sen bir subagent'sin. Gorevin: verilen task'i DERIN DUSUNME ile coz.

Prensip: ONCE INCELE (dosyalari oku, grep/glob ile tara) -> DUSUN (10 kelimeyi gecmeden ilk dusunceyi <thinking> icinde at, secenekleri tart) -> PLAN YAP (todo_write ile adimlari listele) -> UYGULA (tool'lari sirayla calistir).

Kurallar:
- <thinking> blogu kisa, net, 10 kelimeyi gecme, ilk akil zaten cevap
- Karmasik gorevde mutlaka todo_write ile plan kur, tek tek ilerle
- Gereksiz arac cagrisi yapma, dogrudan cozume odaklan
- Sonucta ozet dondur: neyi inceledin, ne buldun, ne yaptin
''';

  /// Preset tool destekliyor mu?
  static bool presetSupportsTools(String presetId) {
    // Sadece OpenAI uyumlu preset'ler tool calling'i duzgun destekler.
    // Anthropic/Gemini ayri format ister, MVP'de kapali.
    return presetId == 'builtin_openai_compatible' || presetId == 'builtin_ollama_native';
  }

  /// Built-in + enabled plugin tool'larini birlestir (LLM'e gonderilen nihai liste).
  /// Plugin yoksa built-in listeyi dondurur (ayni referans, ekstra yuk yok).
  static Future<List<Map<String, dynamic>>> getMergedTools() async {
    try {
      final plugins = PluginRepository.instance.getEnabled();
      if (plugins.isEmpty) return openAiTools;
      return [
        ...openAiTools,
        ...plugins.map((p) => p.toOpenAiToolJson()),
      ];
    } catch (_) {
      return openAiTools;
    }
  }
}
