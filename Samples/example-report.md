<!-- review branch=fix/logout-sometimes/FPM-1653 base=develop iid=965 iteration=1 skill=laconic-review@1 -->
# Code review — `fix/logout-sometimes/FPM-1653` — итерация 1

> Образец отчёта laconic-review. Машинные поля — в `<!-- finding … -->`; проза свободно
> редактируется и публикуется в GitLab **дословно**. Всё, что выше первого `<!-- finding -->`
> (заголовок, TL;DR, сводная таблица), парсер игнорирует — это «шапка для людей». Находки идут
> подряд, без секционных `##`-заголовков между ними (иначе они утекут в тело предыдущего
> комментария). Источники — инлайном внутри находки, не отдельной таблицей в конце.

Серия коммитов сводит login/logout под единый `AuthFlowCoordinator`. Архитектура чище. Остаются
race-окно (C1), отсутствие на него теста (C2) и косметика (N1).

| ID | Severity | Status | Scope | Где |
|---|---|---|---|---|
| C1 | 🟡 concern | ⏳ open | line | `LoginFlowReceiver.swift:18-22` |
| C2 | 🟡 concern | ⏳ open | general | — |
| N1 | 🟢 nit | ⏳ open | line | `StartScreenLoginReceiver.swift:2` |

**Рекомендация:** мёрдж после фикса C1 (или с явным принятием риска). C2 желателен, N1 — на усмотрение.

<!-- finding id=C1 severity=concern status=open scope=line file=flat-ios/Services/Auth/Login/Model/LoginFlowReceiver.swift line=18-22 line_type=new links=C2 -->
### 🟡 C1. Поздний успешный login после завершившегося logout — ⏳ Open

`LoginFlowReceiver` сверяется со статусом `.signingOut`. Но если logout **уже** завершился, статус
`.unauthorized` — и оригинальный `error` (возможно `nil` = успех) проходит, открывая TabBar поверх
свежеподнятого экрана входа.

```swift
let result: LocalizedError? = switch AccountStatus.currentStatus {
case .signingOut, .unauthorized: LoginError.cancelledByLogout
case .signingIn, .signedIn: error
}
```

Альтернатива structurally правильнее — помечать каждую login-сессию `UUID` и сверять при
`onComplete`. См. также C2. Источник: [SE-0306 — Actor reentrancy](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy).

<!-- finding id=C2 severity=concern status=open scope=general links=C1 -->
### 🟡 C2. Нет регрессионного теста на race-окно — ⏳ Open

Сценарий из C1 (login в полёте → logout → `.unauthorized` → поздний успех) не покрыт тестом. Без
него любая правка `AuthFlowCoordinator` рискует тихо вернуть баг. Минимум — unit-тест на переход
статусов в `LoginFlowReceiver`.

<!-- finding id=N1 severity=nit status=open scope=line file=flat-ios/Screens/StartScreen/StartScreenLoginReceiver.swift line=2 line_type=new -->
### 🟢 N1. Заголовок файла не совпадает с именем — ⏳ Open

Шапка говорит `//  StartScreenLoginReceiverAdapter.swift`, файл называется
`StartScreenLoginReceiver.swift` (аналогично у logout-receiver'а). Безвредно, но мешает grep по имени.
