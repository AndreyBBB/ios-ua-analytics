-- safe_divide: reusable macro to avoid division-by-zero errors
-- Usage: {{ safe_divide('revenue', 'installs') }}

{% macro safe_divide(numerator, denominator, default=0) %}
    if({{ denominator }} = 0 or {{ denominator }} is null,
        {{ default }},
        {{ numerator }} / {{ denominator }}
    )
{% endmacro %}
