<script setup>
import { onMounted, ref } from 'vue'

const health = ref('запрос…')
const error = ref('')

async function fetchHealth() {
  try {
    const res = await fetch('/api/v1/health')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    health.value = JSON.stringify(data)
  } catch (e) {
    error.value = `Ошибка: ${e}`
  }
}

onMounted(fetchHealth)
</script>

<template>
  <div class="min-h-screen flex items-center justify-center bg-slate-900">
    <div class="max-w-md p-8 rounded-xl bg-slate-800 shadow-lg text-slate-100">
      <h1 class="text-2xl font-bold mb-4">
        Hello World из Vue 3 + FastAPI
      </h1>
      <p class="mb-2">
        <span class="text-slate-400">GET /api/v1/health →</span>
        <span class="ml-2 font-mono text-emerald-400">{{ health }}</span>
      </p>
      <p v-if="error" class="text-red-400 text-sm">{{ error }}</p>
    </div>
  </div>
</template>