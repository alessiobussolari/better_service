# Caching

Cache dei risultati dei servizi per evitare riesecuzioni costose.

---

## Come Funziona

### Diagramma del Flusso

```
┌─────────────────────────────────────────────────────────────────┐
│                        service.call()                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │     Cache abilitata?         │
              │   (cache_key definito?)      │
              └──────────┬──────────┬────────┘
                         │          │
                      Sì │          │ No
                         │          │
              ┌──────────▼──────┐   │
              │ Genera chiave   │   │
              │ cache:          │   │
              │ key:user:md5    │   │
              └────────┬────────┘   │
                       │            │
              ┌────────▼─────────┐  │
              │ Cache valida?    │  │
              └────┬────────┬────┘  │
                   │        │       │
               Hit │        │ Miss  │
                   │        │       │
         ┌─────────▼───┐    │       │
         │ Ritorna     │    │       │
         │ Result      │    │       │
         │ dalla cache │    │       │
         │ (NO query,  │    │       │
         │ NO process) │    │       │
         └─────────────┘    │       │
                            │       │
              ┌─────────────▼───────▼─────────────────┐
              │        ESECUZIONE COMPLETA            │
              │                                       │
              │  1. search_with  → Query DB           │
              │  2. process_with → Trasformazioni     │
              │  3. transform    → Presenter          │
              │  4. respond_with → Formato risposta   │
              │                                       │
              │  Risultato: BetterService::Result     │
              └───────────────────┬───────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │ Cache abilitata?          │
                    └──────┬──────────┬─────────┘
                           │          │
                        Sì │          │ No
                           │          │
              ┌────────────▼────────┐ │
              │ Memorizza Result    │ │
              │ in Rails.cache      │ │
              │ (TTL: cache_ttl)    │ │
              └────────────┬────────┘ │
                           │          │
                           └────┬─────┘
                                │
                    ┌───────────▼────────────┐
                    │  Ritorna Result        │
                    │  (resource + meta)     │
                    └────────────────────────┘
```

--------------------------------

## Configurazione

### Abilitare il Caching

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list    # Abilita cache con questo identificatore
  cache_ttl 15.minutes        # Durata cache (default: 15 minuti)
  cache_contexts [:products]  # Contesti per invalidazione

  search_with do
    # Questa query viene eseguita SOLO se cache miss
    { items: Product.includes(:category).where(active: true).to_a }
  end
end
```

--------------------------------

## Vantaggi Performance

### Senza Cache

```
Chiamata 1: Query DB (50ms) + Process (20ms) = 70ms
Chiamata 2: Query DB (50ms) + Process (20ms) = 70ms
Chiamata 3: Query DB (50ms) + Process (20ms) = 70ms
Totale: 210ms
```

### Con Cache

```
Chiamata 1: Query DB (50ms) + Process (20ms) + Cache write (1ms) = 71ms
Chiamata 2: Cache read (1ms) = 1ms
Chiamata 3: Cache read (1ms) = 1ms
Totale: 73ms (3x più veloce!)
```

--------------------------------

## Chiave Cache

La chiave cache è composta da:

```
{cache_key}:{user_id}:{params_hash}

Esempio: products_list:user_123:a1b2c3d4
```

- **cache_key**: Identificatore del servizio
- **user_id**: ID utente (o "global" se nil)
- **params_hash**: MD5 dei parametri (params diversi = cache separate)

--------------------------------

## DSL Cache

### cache_key

Abilita il caching e definisce l'identificatore.

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
end
```

--------------------------------

### cache_ttl

Durata della cache (default: 15 minuti).

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
  cache_ttl 1.hour            # 1 ora
  cache_ttl 30.minutes        # 30 minuti
  cache_ttl 86400             # Secondi (24 ore)
end
```

--------------------------------

### cache_contexts

Contesti per invalidazione automatica.

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
  cache_contexts [:products, :inventory]
end
```

--------------------------------

## Auto-Invalidation

I servizi Create/Update/Destroy invalidano automaticamente la cache.

```ruby
class Product::CreateService < Product::BaseService
  cache_contexts [:products]     # Contesti da invalidare
  auto_invalidate_cache true     # Default per CUD services

  # Dopo create: invalida tutte le cache :products per questo user
end
```

### Disabilitare Auto-Invalidation

```ruby
class Product::CreateService < Product::BaseService
  auto_invalidate_cache false    # Gestione manuale
end
```

--------------------------------

## Invalidazione Manuale

### Per Utente e Contesto

```ruby
# Invalida cache :products per utente specifico
BetterService::CacheService.invalidate_for_context(user, :products)
```

### Globale per Contesto

```ruby
# Invalida cache :products per tutti gli utenti
BetterService::CacheService.invalidate_global(:products)
```

### Tutto per Utente

```ruby
# Invalida tutte le cache per un utente
BetterService::CacheService.invalidate_for_user(user)
```

### Chiave Specifica

```ruby
# Invalida una chiave specifica
BetterService::CacheService.invalidate_key("products_list:user_123:abc")
```

--------------------------------

## Cache Invalidation Map

Configura invalidazione a cascata.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.cache_invalidation_map = {
    products: [:inventory, :reports, :homepage],
    orders: [:user_orders, :reports, :dashboard],
    users: [:user_profile, :user_orders]
  }
end
```

### Come Funziona

```ruby
# Quando invalidi :products
BetterService::CacheService.invalidate_for_context(user, :products)

# Vengono invalidati automaticamente:
# - :products
# - :inventory
# - :reports
# - :homepage
```

--------------------------------

## Cache Service API

### Metodi Disponibili

```ruby
# Verifica esistenza chiave
BetterService::CacheService.exist?(key)

# Statistiche cache
BetterService::CacheService.stats
# => {
#   cache_store: "ActiveSupport::Cache::MemoryStore",
#   supports_pattern_deletion: true,
#   supports_async: false
# }
```

--------------------------------

## Eventi Instrumentation

### Cache Events

```ruby
# Cache hit
ActiveSupport::Notifications.subscribe("cache.hit.better_service") do |name, start, finish, id, payload|
  Rails.logger.info "Cache HIT: #{payload[:service]} (key: #{payload[:cache_key]})"
end

# Cache miss
ActiveSupport::Notifications.subscribe("cache.miss.better_service") do |name, start, finish, id, payload|
  Rails.logger.info "Cache MISS: #{payload[:service]} (key: #{payload[:cache_key]})"
end
```

--------------------------------

## Best Practices

### Quando Usare il Caching

```ruby
# Usa il caching per:
# - Index services con query complesse
# - Show services con dati che cambiano raramente
# - Servizi chiamati frequentemente

class Dashboard::StatsService < ApplicationService
  cache_key :dashboard_stats
  cache_ttl 5.minutes           # Aggiorna ogni 5 minuti

  search_with do
    # Query aggregate costose
    {
      total_orders: Order.count,
      revenue: Order.sum(:total),
      top_products: Product.top_selling(10)
    }
  end
end
```

### Quando NON Usare il Caching

```ruby
# NON usare il caching per:
# - Servizi Create/Update/Destroy (invalidano, non cachano)
# - Dati real-time (prezzi, stock)
# - Dati sensibili per utente

class Order::CreateService < Order::BaseService
  # NO cache_key - le scritture non si cachano
  cache_contexts [:orders]      # Ma invalidano la cache orders
end
```

--------------------------------

## Esempio Completo

### IndexService con Cache

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  # Configurazione cache
  cache_key :products_index
  cache_ttl 30.minutes
  cache_contexts [:products]

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:category_id).filled(:integer)
  end

  search_with do
    # Eseguita SOLO se cache miss
    scope = Product.includes(:category).active

    if params[:category_id]
      scope = scope.where(category_id: params[:category_id])
    end

    {
      items: scope.page(params[:page]).per(params[:per_page] || 20).to_a,
      total_count: scope.count
    }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        page: params[:page] || 1,
        per_page: params[:per_page] || 20,
        total_count: data[:total_count]
      }
    }
  end
end

# Prima chiamata: esegue query, salva in cache
# Seconda chiamata (stessi params): ritorna dalla cache istantaneamente
```

### CreateService che Invalida Cache

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  # Invalida cache dopo creazione
  cache_contexts [:products]
  auto_invalidate_cache true    # Default

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  process_with do
    product = Product.create!(
      name: params[:name],
      price: params[:price],
      user: user
    )

    { resource: product }
  end

  # Dopo success:
  # 1. Product creato
  # 2. Cache :products invalidata automaticamente
  # 3. Prossimo IndexService eseguirà query fresca
end
```

--------------------------------
